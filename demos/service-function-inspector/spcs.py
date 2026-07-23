"""
mitmproxy addon — SPCS service function demo handlers.

Each path maps to one CREATE FUNCTION parameter/concept:

  /echo          basic scalar contract
  /typeinfo      type serialization (NUMBER, FLOAT, VARCHAR, BOOLEAN, VARIANT, NULL)
  /batch_size    batch reporting — pair with MAX_BATCH_ROWS
  /null          null detection — pair with CALLED ON NULL INPUT vs STRICT
  /unordered     out-of-order response — shows row-index contract
  /context       echoes SF-CONTEXT-* headers — pair with CONTEXT_HEADERS
  /slow          sleeps past BATCH_TIMEOUT_SECS
  /fail          always HTTP 500 — pair with ON_BATCH_FAILURE = ABORT vs RETURN_NULL
  /retry         fails N times then succeeds — pair with MAX_BATCH_RETRIES

Run:
  mitmproxy --mode reverse:http://localhost:9999 --listen-port 8080 -s spcs.py
"""

import hashlib
import json
import time
import threading
from collections import OrderedDict
from mitmproxy import http

# ---------------------------------------------------------------------------
# Flow grouping — color per path, comment separator on path change
# ---------------------------------------------------------------------------

_PATH_COLORS = {
    "/echo":       "red",
    "/typeinfo":   "green",
    "/batch_size": "yellow",
    "/null":       "orange",
    "/unordered":  "cyan",
    "/context":    "lime",
    "/slow":       "magenta",
    "/fail":       "coral",
    "/retry":      "blue",
}

_last_path: str | None = None
_last_path_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse(flow: http.HTTPFlow) -> list:
    return flow.request.json().get("data", [])

def _ok(flow: http.HTTPFlow, rows: list) -> None:
    body = json.dumps({"data": rows}).encode()
    flow.response = http.Response.make(200, body, {"Content-Type": "application/json"})

def _err(flow: http.HTTPFlow, status: int = 500, msg: str = "error") -> None:
    flow.response = http.Response.make(status, msg.encode(), {"Content-Type": "text/plain"})


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

def _echo(flow, rows):
    """Basic service function contract: one result per input row."""
    _ok(flow, [[r[0], r[1] if len(r) > 1 else None] for r in rows])


def _typeinfo(flow, rows):
    """Shows how Snowflake types arrive as Python/JSON types.

    Pair with:
      CREATE FUNCTION demo_typeinfo(n NUMBER, f FLOAT, s VARCHAR, b BOOLEAN, v VARIANT)
        RETURNS VARCHAR ...
    """
    out = []
    for r in rows:
        desc = ", ".join(f"arg{i}={type(v).__name__}({v!r})" for i, v in enumerate(r[1:], 1))
        out.append([r[0], desc or "(no args)"])
    _ok(flow, out)


def _batch_size(flow, rows):
    """Reports row count and payload size for this batch.

    Pair with MAX_BATCH_ROWS = N — each call will show at most N rows.
    Watch mitmproxy: without MAX_BATCH_ROWS you'll see large batches up to
    Snowflake's internal size limit; with it you'll see many smaller ones.
    """
    n = len(rows)
    kb = len(flow.request.content) / 1024
    summary = f"rows={n} payload={kb:.1f}KB"
    _ok(flow, [[r[0], summary] for r in rows])


def _null(flow, rows):
    """Shows which argument positions arrived as null (Python None / JSON null).

    Pair with two functions:
      CALLED ON NULL INPUT  — Snowflake sends rows with NULLs; service sees null
      RETURNS NULL ON NULL INPUT / STRICT — Snowflake skips those rows entirely;
                                            service never sees them
    """
    out = []
    for r in rows:
        null_pos = [i for i, v in enumerate(r[1:], 1) if v is None]
        out.append([r[0], f"nulls at {null_pos}" if null_pos else "no nulls"])
    _ok(flow, out)


def _unordered(flow, rows):
    """Returns rows in reverse order to show Snowflake reassembles by row index.

    The result set in SQL will still be in the correct order because Snowflake
    matches output rows back to input rows via the row index (r[0]).
    """
    _ok(flow, [[r[0], f"row {r[0]} processed"] for r in reversed(rows)])


def _context(flow, rows):
    """Echoes SF-CONTEXT-* headers back as the result value.

    Pair with CONTEXT_HEADERS = (CURRENT_USER, CURRENT_ROLE, ...).
    The header names Snowflake injects follow the pattern:
      sf-context-current-user, sf-context-current-role, etc.
    """
    ctx = {k: v for k, v in flow.request.headers.items()
           if k.lower().startswith("sf-context")}
    _ok(flow, [[r[0], json.dumps(ctx)] for r in rows])


_SLOW_SECS = 6  # set higher than BATCH_TIMEOUT_SECS in the CREATE FUNCTION

def _slow(flow, rows):
    """Sleeps past the timeout to trigger BATCH_TIMEOUT_SECS handling.

    Pair with BATCH_TIMEOUT_SECS = 3 (or any value < _SLOW_SECS).
    """
    time.sleep(_SLOW_SECS)
    _ok(flow, [[r[0], f"slept {_SLOW_SECS}s"] for r in rows])


def _fail(flow, rows):
    """Always returns HTTP 500.

    Pair with two functions using the same /fail path:
      ON_BATCH_FAILURE = ABORT        — query errors out
      ON_BATCH_FAILURE = RETURN_NULL  — affected rows return NULL silently
    """
    _err(flow, 500, "deliberate failure")


_RETRY_FAIL_TIMES = 2  # fail this many times before succeeding
_RETRY_CACHE_MAX  = 256

# OrderedDict used as a bounded LRU: key -> attempt count.
# Keyed per-batch so parallel batches and repeated queries don't share state.
_retry_cache: OrderedDict[str, int] = OrderedDict()
_retry_cache_lock = threading.Lock()

# Headers Snowflake may inject that uniquely identify a batch.
# sf-external-function-query-batch-id  — unique per batch within a query (preferred)
# sf-external-function-current-query-id — unique per query
_BATCH_ID_HEADERS = (
    "sf-external-function-query-batch-id",
    "sf-external-function-current-query-id",
)

def _batch_key(flow: http.HTTPFlow) -> str:
    """Stable key for a batch: same on every retry, different for each new batch."""
    for header in _BATCH_ID_HEADERS:
        val = flow.request.headers.get(header)
        if val:
            return f"{header}:{val}"
    # Fallback: hash the raw body — retries send the identical payload
    return "body:" + hashlib.sha256(flow.request.content).hexdigest()[:16]

def _retry(flow, rows):
    """Fails _RETRY_FAIL_TIMES times then succeeds, tracked per batch.

    Pair with MAX_BATCH_RETRIES = N (must be >= _RETRY_FAIL_TIMES).
    Each distinct batch gets its own counter, so repeated queries and
    parallel batches don't interfere with each other.
    """
    key = _batch_key(flow)
    with _retry_cache_lock:
        attempt = _retry_cache.get(key, 0) + 1
        _retry_cache[key] = attempt
        _retry_cache.move_to_end(key)
        while len(_retry_cache) > _RETRY_CACHE_MAX:
            _retry_cache.popitem(last=False)
    if attempt <= _RETRY_FAIL_TIMES:
        _err(flow, 500, f"transient failure (attempt {attempt} of {_RETRY_FAIL_TIMES})")
    else:
        _ok(flow, [[r[0], f"succeeded on attempt {attempt}"] for r in rows])


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

_ROUTES = {
    "/echo":       _echo,
    "/typeinfo":   _typeinfo,
    "/batch_size": _batch_size,
    "/null":       _null,
    "/unordered":  _unordered,
    "/context":    _context,
    "/slow":       _slow,
    "/fail":       _fail,
    "/retry":      _retry,
}

def _annotate(flow: http.HTTPFlow, path: str) -> None:
    """Color-mark the flow and add a separator comment when the path changes."""
    global _last_path
    flow.marked = _PATH_COLORS.get(path, "")
    with _last_path_lock:
        if path != _last_path:
            flow.comment = f"── {path} " + "─" * max(0, 30 - len(path))
            _last_path = path


def request(flow: http.HTTPFlow) -> None:
    if flow.request.method == "GET":
        flow.response = http.Response.make(200, b"ok", {"Content-Type": "text/plain"})
        return

    if flow.request.method != "POST":
        return

    path = flow.request.path.split("?")[0].rstrip("/") or "/echo"
    _annotate(flow, path)

    handler = _ROUTES.get(path)
    if handler is None:
        _err(flow, 404, f"unknown path '{path}'. available: {sorted(_ROUTES)}")
        return

    try:
        rows = _parse(flow)
        handler(flow, rows)
    except Exception as exc:
        _err(flow, 500, f"addon error in {path}: {exc}")
