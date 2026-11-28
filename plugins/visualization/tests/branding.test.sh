#!/usr/bin/env bash
# test-scope: plugins/visualization/lib/html-branding.mjs plugins/visualization/reference/html-tokens.css plugins/visualization/reference/html-loop-closure.html plugins/visualization/reference/html-chrome.html plugins/visualization/lib/view-settings.mjs
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/branding.test.mjs"
