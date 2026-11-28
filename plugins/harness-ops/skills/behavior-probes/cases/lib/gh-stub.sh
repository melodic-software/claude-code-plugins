#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$1/bin"
cat >"$1/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$(dirname "$0")/../gh-calls.log"
printf 'gh-stub-marker: %s\n' "$*"
STUB
chmod +x "$1/bin/gh"
