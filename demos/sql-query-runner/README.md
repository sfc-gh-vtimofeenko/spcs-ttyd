> [!WARNING]
> This service exists for illustration purposes only. It exposes a console to
> run SQL and is prone to SQL injection. Do not run it in production or under a
> role that may have access to non-demo data.

This directory contains a Flask web service that demonstrates running SQL queries
in SPCS with different authentication contexts:

1. **Service Owner** – Uses the service owner's OAuth token from
   `/snowflake/session/token`
2. **Visiting User** – Uses restricted caller's rights by combining the service
   token with the user token from `Sf-Context-Current-User-Token` header

## Features

- Web UI with SQL query editor
- Quick-access buttons for common queries like `SELECT CURRENT_USER()`
- Side-by-side comparison of results when running the same query in both contexts
- Visual indication of whether user token is available

## Running

If you have `nix` installed and `nix` command enabled, script can be run as is:

```bash
./runme-nix
```

Otherwise, use `uv run --script` to run it.

The service listens on port 8000 by default. Set `FLASK_RUN_PORT` to override:

```bash
FLASK_RUN_PORT=9000 ./runme-nix
```

## Configuration

For the "Run as User" functionality to work, you need to configure the service
with caller's rights. See [Snowflake documentation on configuring caller's rights][1].

[1]: https://docs.snowflake.com/en/developer-guide/snowpark-container-services/additional-considerations-services-jobs#label-spcs-callers-rights

