This demo uses [`mitmproxy`](https://mitmproxy.org/) as a live HTTP inspector to
illustrate parameters of
[`CREATE FUNCTION (Snowpark Container Services)`](https://docs.snowflake.com/en/sql-reference/sql/create-function-spcs)
from the service's perspective.

The code effectively starts an instrumented webserver that responds to the
service functions. `mitmproxy` is used to show the requests headers and data.

## Handlers

| Path | Demonstrates |
|---|---|
| `/echo` | Basic scalar contract — one result row per input row |
| `/typeinfo` | Type serialization — how `NUMBER`, `FLOAT`, `VARCHAR`, `BOOLEAN`, `VARIANT`, `NULL` arrive as Python/JSON types |
| `/batch_size` | `MAX_BATCH_ROWS` — reports `rows=N payload=XKB` per batch so you can see Snowflake's automatic batching |
| `/null` | `CALLED ON NULL INPUT` vs `RETURNS NULL ON NULL INPUT` — whether rows with NULL args reach the service |
| `/unordered` | Row-index contract — service returns rows reversed; SQL result is still correct |
| `/context` | `CONTEXT_HEADERS` — injects `sf-context-*` request headers; service echoes them back |
| `/slow` | `BATCH_TIMEOUT_SECS` — sleeps 6 seconds; pair with timeout 3 to trigger error, 10 to succeed |
| `/fail` | `ON_BATCH_FAILURE` — always HTTP 500; pair with `ABORT` vs `RETURN_NULL` |
| `/retry` | `MAX_BATCH_RETRIES` — fails twice then succeeds |

## Running

With `nix` available:

```bash
./runme-nix
```

This starts mitmproxy on port 8080 (override with `LISTEN_PORT`). The reverse
proxy target (`localhost:9999`) is never reached — the addon short-circuits
every POST in the `request` hook before forwarding.

Without nix:

```bash
pip install mitmproxy
mitmproxy --mode reverse:http://localhost:9999 --listen-port 8080 -s spcs.py
```

## Connecting Snowflake

Deploy the service to SPCS, then substitute `<SERVICE>` and `<ENDPOINT>` in
`demo_functions.sql` and run the file. Each `SELECT` statement at the bottom
of a section exercises the corresponding concept.

### Batching demo

The batch section includes both a small sanity run (10 rows) and a ~30 MB run
(35 000 rows × 900-byte strings) to force Snowflake's automatic size-based
batching. Run the default and small variants side-by-side in `mitmproxy` to
compare request counts and payload sizes:

```sql
-- default: expect 3–6 large requests
SELECT demo_batch_default(REPEAT('x', 900)) FROM TABLE(GENERATOR(ROWCOUNT => 35000));

-- MAX_BATCH_ROWS = 3: expect ~11 667 small requests (slow — reduce ROWCOUNT for demos)
SELECT demo_batch_small(REPEAT('x', 900))   FROM TABLE(GENERATOR(ROWCOUNT => 35000));
```

