#!/usr/bin/env bash
# gh-stub.sh <dir>: <dir>/bin/gh, a stub that logs its arguments to
# <dir>/gh-calls.log and prints gh-stub-marker, so a gh call the
# intake-permissions cases let through touches no real issue. The cases'
# settings.json puts <dir>/bin first on PATH.
set -euo pipefail
mkdir -p "$1/bin"
cat >"$1/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$(dirname "$0")/../gh-calls.log"
printf 'gh-stub-marker: %s\n' "$*"
STUB
chmod +x "$1/bin/gh"
