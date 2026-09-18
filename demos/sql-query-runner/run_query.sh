#!/usr/bin/env bash
set -euo pipefail

# USAGE: echo "$STATEMENTS" | ./run_query.sh [owner|caller]
#
# Reads one or more ';'-separated SQL statements from stdin and posts them to
# the sql-query-runner /execute endpoint, running them all in one session.
#
# Requires:
#   - jq (for safe JSON encoding of the query text)
#   - a PAT in a ".pat" file next to this script
#   - $URL set to the service's ingress host (no scheme, e.g. export URL=...)

MODE_ARG="${1:-owner}"
case "$MODE_ARG" in
    owner)          MODE="owner" ;;
    caller|user)    MODE="user" ;;
    *)
        echo "Usage: $0 [owner|caller]" >&2
        exit 1
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAT="$(<"${SCRIPT_DIR}/.pat")"
QUERY="$(cat)"

curl --location "https://${URL}/execute" \
    --header "Authorization: Snowflake Token=\"${PAT}\"" \
    --header 'Content-Type: application/json' \
    --data "$(jq -n --arg mode "$MODE" --arg query "$QUERY" '{mode: $mode, query: $query}')"
