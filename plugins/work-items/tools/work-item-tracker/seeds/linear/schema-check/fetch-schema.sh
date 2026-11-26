#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HERE/schema.graphql"
URL="https://raw.githubusercontent.com/linear/linear/master/packages/sdk/src/schema.graphql"

if ! curl -fsSL --proto '=https' "$URL" -o "$DEST"; then
  printf 'fetch-schema.sh: %s\n' >&2 \
    "could not fetch the Linear SDL from $URL" \
    'if your environment proxies outbound HTTPS, make curl aware of it' \
    '(HTTPS_PROXY and a CA bundle) before re-running.'
  exit 1
fi

if ! grep -q '^type Issue ' "$DEST"; then
  # shellcheck disable=SC2016  # the backticks are literal message text, not a command substitution
  printf 'fetch-schema.sh: %s does not look like the Linear SDL (no `type Issue`) — refusing it\n' "$DEST" >&2
  rm -f "$DEST"
  exit 1
fi

printf 'fetch-schema.sh: wrote %s (%s bytes)\n' "$DEST" "$(wc -c <"$DEST" | tr -d ' ')"
