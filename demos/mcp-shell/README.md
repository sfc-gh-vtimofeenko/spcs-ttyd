# SPCS MCP Shell

This demo speeds up remote development in SPCS. It runs an MCP server which
executes commands from agents in shell panes, letting you try out
packages/settings without the rebuild loop.

Combined with the web shell session, you can watch and monitor command execution
in the browser, or spawn a long running session inside container and then
connect to it using clients.

> [!CAUTION]
> MCP server runs behind Snowflake authentication, but allows code execution
> as the service main identity. Please don't run this under a privileged role.

## Tools

- `start_shell_session`: start a command in a new pane and return a shell session ID
- `read_shell_session`: read new output from the session's log, from an offset
- `read_shell_pane`: read what the session's pane currently shows
- `send_shell_input`: type text into a running session's pane
- `stop_shell_session`: stop a session if needed and close its pane
- `list_shell_sessions`: list tracked sessions

Command output is shown live in the pane and is also logged to a file.

Terminology: a *shell session* is one command started by an agent.

## Setup

Start it from the demo menu in the web shell, or directly:

```bash
./runme-nix
```

Default port it's listening on is `:8001` which may be overriden by setting
`MCP_PORT` variable. Server runs until stopped using `Ctrl+C`.

## Connect Cortex Code

Create a role-restricted PAT for the Snowflake user that should access the
service, then find the ingress hostname with `SHOW ENDPOINTS IN SERVICE`.
Configure the HTTP MCP server with the PAT in the `Snowflake Token` header:

```bash
cortex mcp add spcs-shell https://<ingress-host>/mcp \
  --type http \
  -H 'Authorization: Snowflake Token="${SPCS_MCP_PAT}"'
```

Keep `SPCS_MCP_PAT` in the local environment or keychain rather than committing
it to the MCP configuration. The PAT authenticates the caller at SPCS ingress;
commands started by this demo still run as the service container identity.

## Try it

With the web shell open in a browser next to your Cortex chat, ask:

```text
Using the spcs-shell MCP server, start a command that prints a line with the
current time every 2 seconds for 60 seconds, and fails with exit code 3 at the
end. Do not wait for it to finish. Tell me the shell session ID, then:
1. After about 10 seconds, call read_shell_session and quote only the new lines.
2. Call read_shell_session again with the returned next_offset and confirm you got
   only lines you haven't seen.
3. Call read_shell_pane and tell me whether it matches what read_shell_session showed.
4. When the shell session ends, report its status and exit code, then call stop_shell_session
   to close the pane.
```

Expected: a new `shell-session-<id>` pane appears in the web shell and prints the lines
live, the second `read_shell_session` returns only newer lines, `read_shell_pane` shows the
same text plus the `[shell session <id> exited with code 3]` footer once finished, and
the final status is `completed` with `exit_code` 3.
