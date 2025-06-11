This directory contains a single file to perform sample queries using [Cortex
Agent REST API][1]. The python script uses the values that are available by
default in the container.

The script itself relies on `nix` and uses `uv` in `--script` [mode][uv-scripts]
so that it's self-contained. It can be used in an arbitrary container as long as
the container includes `python` and `uv`.

The two versions of the script in this directory contain the same code, but [one][2]
uses `nix shell` (suitable for flakes) and [the other][3] uses standard `nix-shell`.


[1]: https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-rest-api
[2]: ./runme-nix-command
[3]: ./runme-nix-shell
[uv-scripts]: https://docs.astral.sh/uv/guides/scripts/
