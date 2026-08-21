#!/usr/bin/env bash
# Fetch Linear's published GraphQL SDL next to this script, for validate.mjs / negative.mjs.
#
# The SDL is ~1.2 MB of vendored upstream text, so it is fetched on demand rather than
# committed: vendoring it would put a megabyte of someone else's schema in this repo and
# freeze it at whatever day it was copied. Fetching keeps the check honest — it validates
# against what Linear publishes now, and a drift that breaks the adapter shows up as a
# validation failure rather than as silence.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HERE/schema.graphql"
URL="https://raw.githubusercontent.com/linear/linear/master/packages/sdk/src/schema.graphql"

# This is the same file the adapter's own comments cite (see common.sh's schema references).
if ! curl -fsSL --proto '=https' "$URL" -o "$DEST"; then
  printf 'fetch-schema.sh: could not fetch the Linear SDL from %s\n' "$URL" >&2
  printf 'fetch-schema.sh: if your environment proxies outbound HTTPS, make curl aware of it\n' >&2
  printf 'fetch-schema.sh: (HTTPS_PROXY and a CA bundle) before re-running.\n' >&2
  exit 1
fi

# A truncated or error-page download would otherwise fail later as a confusing parse error.
if ! grep -q '^type Issue ' "$DEST"; then
  # shellcheck disable=SC2016  # the backticks are literal message text, not a command substitution
  printf 'fetch-schema.sh: %s does not look like the Linear SDL (no `type Issue`) — refusing it\n' "$DEST" >&2
  rm -f "$DEST"
  exit 1
fi

printf 'fetch-schema.sh: wrote %s (%s bytes)\n' "$DEST" "$(wc -c <"$DEST" | tr -d ' ')"
