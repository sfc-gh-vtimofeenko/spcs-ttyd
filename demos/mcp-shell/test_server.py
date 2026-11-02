from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from server import Session, SessionManager, _clean_terminal_text


class FakeZellij:
    zellij_session = "test"

    def __init__(self) -> None:
        self.commands: list[tuple[str, str]] = []
        self.closed: list[str] = []
        self.inputs: list[tuple[str, str]] = []
        self.screens: dict[str, str] = {}
        self.next_pane = 0

    def ensure_zellij_session(self) -> None:
        return None

    def create_pane(self, session: Session, command: str) -> str:
        self.next_pane += 1
        self.commands.append((session.shell_session_id, command))
        return f"terminal_{self.next_pane}"

    def write_chars(self, pane_id: str, text: str) -> None:
        self.inputs.append((pane_id, text))

    def close_pane(self, pane_id: str) -> None:
        self.closed.append(pane_id)

    def dump_screen(self, pane_id: str, full: bool = False) -> str:
        if pane_id not in self.screens:
            raise subprocess.CalledProcessError(1, "zellij")
        return self.screens[pane_id]


class SessionManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.zellij = FakeZellij()
        self.sessions = SessionManager(self.root / "state", self.root / "workspace", self.zellij)

    def test_start_and_read_session(self) -> None:
        result = self.sessions.start_shell_session("printf hello")
        session = self.sessions._read_metadata(result["shell_session_id"])
        self.sessions._output_path(session.shell_session_id).write_text("hello\n")
        self.sessions._write_status(session.shell_session_id, "completed")
        self.sessions._exit_code_path(session.shell_session_id).write_text("0")

        output = self.sessions.read_shell_session(session.shell_session_id)

        self.assertEqual(output["output"], "hello\n")
        self.assertEqual(output["status"], "completed")
        self.assertTrue(self.zellij.commands)

    def test_read_shell_session_is_incremental(self) -> None:
        result = self.sessions.start_shell_session("long")
        self.sessions._output_path(result["shell_session_id"]).write_text("one\ntwo\n")

        first = self.sessions.read_shell_session(result["shell_session_id"], max_bytes=4)
        second = self.sessions.read_shell_session(result["shell_session_id"], offset=first["next_offset"])

        self.assertEqual(first["output"], "one\n")
        self.assertTrue(first["has_more"])
        self.assertEqual(second["output"], "two\n")
        self.assertFalse(second["has_more"])

    def test_read_shell_session_strips_terminal_noise(self) -> None:
        result = self.sessions.start_shell_session("colors")
        self.sessions._output_path(result["shell_session_id"]).write_text("\x1b[31mred\x1b[0m\r\nprogress 10%\rprogress 100%\r\n")

        cleaned = self.sessions.read_shell_session(result["shell_session_id"])["output"]
        raw = self.sessions.read_shell_session(result["shell_session_id"], strip_ansi=False)["output"]

        self.assertEqual(cleaned, "red\nprogress 100%\n")
        self.assertIn("\x1b[31m", raw)

    def test_read_shell_pane_returns_tail_of_screen(self) -> None:
        result = self.sessions.start_shell_session("watch")
        self.zellij.screens[result["pane_id"]] = "a\nb\nc\nd\n\n\n"

        pane = self.sessions.read_shell_pane(result["shell_session_id"], max_lines=2)

        self.assertEqual(pane["screen"], "c\nd")
        self.assertEqual(pane["total_lines"], 4)
        self.assertTrue(pane["truncated"])

    def test_read_shell_pane_reports_closed_pane(self) -> None:
        result = self.sessions.start_shell_session("watch")

        with self.assertRaisesRegex(ValueError, "not available"):
            self.sessions.read_shell_pane(result["shell_session_id"])

    def test_input_is_sent_to_the_session_pane(self) -> None:
        result = self.sessions.start_shell_session("read input")

        self.sessions.send_shell_input(result["shell_session_id"], "answer\n")

        self.assertEqual(self.zellij.inputs, [(result["pane_id"], "answer\n")])

    def test_stop_marks_running_session_stopped_and_closes_pane(self) -> None:
        result = self.sessions.start_shell_session("sleep 100")

        stopped = self.sessions.stop_shell_session(result["shell_session_id"])

        self.assertEqual(stopped["status"], "stopped")
        self.assertEqual(self.zellij.closed, [result["pane_id"]])

    def test_stop_closes_pane_of_finished_session_and_keeps_status(self) -> None:
        result = self.sessions.start_shell_session("true")
        self.sessions._write_status(result["shell_session_id"], "completed")

        stopped = self.sessions.stop_shell_session(result["shell_session_id"])

        self.assertEqual(stopped["status"], "completed")
        self.assertEqual(self.zellij.closed, [result["pane_id"]])

    def test_rejects_unknown_session_and_outside_workspace(self) -> None:
        with self.assertRaisesRegex(ValueError, "Unknown session id"):
            self.sessions.read_shell_session("000000000000")
        with self.assertRaisesRegex(ValueError, "inside"):
            self.sessions.start_shell_session("pwd", cwd="/")

    def test_wrapper_runs_command_on_a_pty_without_redirecting_the_pane(self) -> None:
        self.sessions.start_shell_session("true")

        wrapper = self.zellij.commands[0][1]

        self.assertIn("script -qefc", wrapper)
        self.assertNotIn("> /", wrapper.split("script", 1)[0])


class TerminalTextTests(unittest.TestCase):
    def test_plain_text_is_unchanged(self) -> None:
        self.assertEqual(_clean_terminal_text("a\nb\n"), "a\nb\n")

    def test_osc_title_sequences_are_removed(self) -> None:
        self.assertEqual(_clean_terminal_text("\x1b]0;title\x07hi"), "hi")


class RunningZellij(FakeZellij):
    """Runs the generated wrapper to completion before create_pane returns."""

    def __init__(self, bin_dir: Path) -> None:
        super().__init__()
        self.bin_dir = bin_dir
        self.wrapper_output = ""

    def create_pane(self, session: Session, command: str) -> str:
        env = {**os.environ, "PATH": f"{self.bin_dir}{os.pathsep}{os.environ['PATH']}"}
        completed = subprocess.run(
            ["bash", "-c", command], env=env, cwd=session.cwd, check=False, capture_output=True, text=True
        )
        self.wrapper_output = completed.stdout
        return super().create_pane(session, command)


class WrapperExecutionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        # Mimics util-linux `script -qefc CMD FILE`: show output, log it, keep the exit code
        stub = bin_dir / "script"
        stub.write_text('#!/bin/bash\nbash -c "$2" 2>&1 | tee "$3"\nexit "${PIPESTATUS[0]}"\n')
        stub.chmod(0o755)
        self.zellij = RunningZellij(bin_dir)
        self.sessions = SessionManager(self.root / "state", self.root / "workspace", self.zellij)

    def test_fast_command_is_not_left_running(self) -> None:
        started = self.sessions.start_shell_session("echo hello")

        result = self.sessions.read_shell_session(started["shell_session_id"])

        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(result["output"], "hello\n")

    def test_output_is_shown_in_the_pane_and_logged(self) -> None:
        started = self.sessions.start_shell_session("echo visible")

        self.assertIn("visible", self.zellij.wrapper_output)
        self.assertIn("exited with code 0", self.zellij.wrapper_output)
        self.assertEqual(self.sessions.read_shell_session(started["shell_session_id"])["output"], "visible\n")

    def test_failing_command_reports_exit_code(self) -> None:
        started = self.sessions.start_shell_session("echo oops >&2; exit 3")

        result = self.sessions.read_shell_session(started["shell_session_id"])

        self.assertEqual(result["status"], "completed")
        self.assertEqual(result["exit_code"], 3)
        self.assertEqual(result["output"], "oops\n")

    def test_finished_session_is_not_rerun(self) -> None:
        started = self.sessions.start_shell_session("echo once")
        _, wrapper = self.zellij.commands[0]
        env = {**os.environ, "PATH": f"{self.zellij.bin_dir}{os.pathsep}{os.environ['PATH']}"}

        rerun = subprocess.run(["bash", "-c", wrapper], env=env, capture_output=True, text=True, check=False)

        self.assertIn("already finished", rerun.stdout)
        self.assertEqual(self.sessions.read_shell_session(started["shell_session_id"])["output"], "once\n")


if __name__ == "__main__":
    unittest.main()
