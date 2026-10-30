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
if [ -z "${PAT:-}" ]; then
    PAT_FILE="${PAT_FILE:-${SCRIPT_DIR}/.pat}"
    if [ ! -r "$PAT_FILE" ]; then
        echo "Set PAT or PAT_FILE to a readable programmatic access token file." >&2
        exit 1
    fi
    PAT="$(<"$PAT_FILE")"
fi
QUERY="$(cat)"
SERVICE_URL="${URL:?Set URL to the service ingress host or URL.}"
SERVICE_URL="${SERVICE_URL#https://}"
SERVICE_URL="${SERVICE_URL#http://}"
SERVICE_URL="${SERVICE_URL%/}"

curl --fail --location "https://${SERVICE_URL}/execute" \
    --header "Authorization: Snowflake Token=\"${PAT}\"" \
    --header 'Content-Type: application/json' \
    --data "$(jq -n --arg mode "$MODE" --arg query "$QUERY" '{mode: $mode, query: $query}')"
