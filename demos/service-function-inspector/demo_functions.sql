-- Prerequisites: replace <SERVICE> and <ENDPOINT> throughout.
-- Each function maps to one path/concept in spcs.py.

-- ---------------------------------------------------------------------------
-- 1. Basic scalar contract  (/echo)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_echo(v VARCHAR)
  RETURNS VARCHAR
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/echo';

SELECT demo_echo(name) FROM (VALUES ('alice'), ('bob')) t(name);


-- ---------------------------------------------------------------------------
-- 2. Type serialization  (/typeinfo)
-- Shows how each Snowflake type arrives as a Python/JSON type.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_typeinfo(n NUMBER, f FLOAT, s VARCHAR, b BOOLEAN, v VARIANT)
  RETURNS VARCHAR
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/typeinfo';

SELECT demo_typeinfo(42, 3.14, 'hello', true, parse_json('{"k":1}'));


-- ---------------------------------------------------------------------------
-- 3. MAX_BATCH_ROWS  (/batch_size)
-- Without MAX_BATCH_ROWS Snowflake may send all rows in one batch.
-- With MAX_BATCH_ROWS = 3 each batch is at most 3 rows — watch in mitmproxy.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_batch_default(v VARCHAR)
  RETURNS VARCHAR
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/batch_size';

CREATE OR REPLACE FUNCTION demo_batch_small(v VARCHAR)
  RETURNS VARCHAR
  MAX_BATCH_ROWS = 3
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/batch_size';

-- ---------------------------------------------------------------------------
-- Tiny run: confirm routing works (10 rows, single batch expected).
-- ---------------------------------------------------------------------------
SELECT demo_batch_default(seq4()::VARCHAR) FROM TABLE(GENERATOR(ROWCOUNT => 10));
SELECT demo_batch_small(seq4()::VARCHAR)   FROM TABLE(GENERATOR(ROWCOUNT => 10));

-- ---------------------------------------------------------------------------
-- Large run: ~30 MB of payload to force Snowflake's automatic batching.
--
-- Each row is REPEAT('x', 900) ≈ 912 bytes in JSON.
-- 35 000 rows × 912 B ≈ 30 MB total.
--
-- demo_batch_default (no MAX_BATCH_ROWS):
--   Snowflake splits at its internal size limit (~5–10 MB).
--   Expect 3–6 requests in mitmproxy, each reporting a large row count.
--
-- demo_batch_small (MAX_BATCH_ROWS = 3):
--   Forces tiny batches regardless of payload size.
--   Expect ~11 667 requests, each reporting rows=3 payload≈2.7KB.
--   Use this to show the row-count cap, NOT for load testing.
-- ---------------------------------------------------------------------------
SELECT demo_batch_default(REPEAT('x', 900)) FROM TABLE(GENERATOR(ROWCOUNT => 35000));
SELECT demo_batch_small(REPEAT('x', 900))   FROM TABLE(GENERATOR(ROWCOUNT => 35000));


-- ---------------------------------------------------------------------------
-- 4. NULL handling  (/null)
-- CALLED ON NULL INPUT  — Snowflake forwards rows that contain NULL args.
-- STRICT                — Snowflake skips NULL-arg rows; service never sees them.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_null_called(v VARCHAR)
  RETURNS VARCHAR
  CALLED ON NULL INPUT
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/null';

CREATE OR REPLACE FUNCTION demo_null_strict(v VARCHAR)
  RETURNS VARCHAR
  RETURNS NULL ON NULL INPUT   -- synonym: STRICT
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/null';

SELECT demo_null_called(v), demo_null_strict(v)
FROM (VALUES ('hello'), (NULL), ('world')) t(v);


-- ---------------------------------------------------------------------------
-- 5. Row-index contract  (/unordered)
-- The service returns rows in reverse order. Snowflake reassembles correctly
-- because it matches output rows to input rows via the row index.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_unordered(v VARCHAR)
  RETURNS VARCHAR
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/unordered';

SELECT v, demo_unordered(v)
FROM (VALUES ('first'), ('second'), ('third'), ('fourth'), ('fifth')) t(v);


-- ---------------------------------------------------------------------------
-- 6. CONTEXT_HEADERS  (/context)
-- Snowflake injects the requested context values as HTTP headers.
-- The service echoes them back so you can see the header names and values.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_context(v VARCHAR)
  RETURNS VARCHAR
  CONTEXT_HEADERS = (CURRENT_USER, CURRENT_ROLE, CURRENT_WAREHOUSE)
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/context';

SELECT demo_context('any');


-- ---------------------------------------------------------------------------
-- 7. BATCH_TIMEOUT_SECS  (/slow)
-- The service sleeps 6 seconds. Set timeout < 6 to trigger the error.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_slow_timeout(v VARCHAR)
  RETURNS VARCHAR
  BATCH_TIMEOUT_SECS = 3          -- service sleeps 6s → will time out
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/slow';

CREATE OR REPLACE FUNCTION demo_slow_ok(v VARCHAR)
  RETURNS VARCHAR
  BATCH_TIMEOUT_SECS = 10         -- service sleeps 6s → will succeed
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/slow';

SELECT demo_slow_timeout('x');    -- expect: error
SELECT demo_slow_ok('x');         -- expect: "slept 6s"


-- ---------------------------------------------------------------------------
-- 8. ON_BATCH_FAILURE  (/fail — always HTTP 500)
-- ABORT       — the entire query errors out
-- RETURN_NULL — failed-batch rows silently become NULL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_fail_abort(v VARCHAR)
  RETURNS VARCHAR
  ON_BATCH_FAILURE = ABORT
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/fail';

CREATE OR REPLACE FUNCTION demo_fail_null(v VARCHAR)
  RETURNS VARCHAR
  ON_BATCH_FAILURE = RETURN_NULL
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/fail';

SELECT demo_fail_abort('x');      -- expect: query error
SELECT demo_fail_null('x');       -- expect: NULL


-- ---------------------------------------------------------------------------
-- 9. MAX_BATCH_RETRIES  (/retry)
-- The service fails the first 2 attempts then succeeds.
-- Set MAX_BATCH_RETRIES >= 2 to observe recovery; 1 to observe failure.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION demo_retry_ok(v VARCHAR)
  RETURNS VARCHAR
  MAX_BATCH_RETRIES = 3           -- enough retries → succeeds on attempt 3
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/retry';

CREATE OR REPLACE FUNCTION demo_retry_fail(v VARCHAR)
  RETURNS VARCHAR
  MAX_BATCH_RETRIES = 1           -- not enough retries → fails
  ON_BATCH_FAILURE = ABORT
  SERVICE = <SERVICE>
  ENDPOINT = <ENDPOINT>
  AS '/retry';

SELECT demo_retry_ok('x');        -- expect: "succeeded on attempt 3"
SELECT demo_retry_fail('x');      -- expect: query error
