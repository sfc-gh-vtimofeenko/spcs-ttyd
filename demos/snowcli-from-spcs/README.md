The default nix-based image provides [Snowflake CLI][index].

It can be used to connect to Snowflake like so:

```shell
echo "[connections.default]" | /bin/snow \
    --config-file /dev/stdin \
    sql \
    --query "SELECT current_warehouse()" \
    --host "$SNOWFLAKE_HOST" \
    --authenticator "OAUTH" \
    --account "$SNOWFLAKE_ACCOUNT" \
    --token-file-path /snowflake/session/token
```

Optional additions:

- `--format json` to print results as JSON
- Pipe to `jq` for pretty printing/parsing

[index]: https://docs.snowflake.com/en/developer-guide/snowflake-cli/index
