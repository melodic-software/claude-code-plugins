#!/usr/bin/env bash
# A user settings.json whose statusLine already runs a command with quotes,
# $() and parentheses, so apply cache-line must wrap it through --wire
# (setup SKILL.md apply cache-line steps 2-3). The runner sets HOME to the
# run's temporary home for a scaffold script
# (https://code.claude.com/docs/en/plugin-evals, "Set up fixtures and mocks").
# It also places a byte-identical cache-line.mjs, because the run home's
# ~/.claude is read-only inside the eval sandbox: step 1's copy then finds the
# copy current and writes nothing. The guard refuses the account's real home
# and never overwrites a file.
set -euo pipefail

refuse() {
  echo "refusing: $1" >&2
  exit 1
}

[[ -n "${HOME:-}" && -d "$HOME" ]] || refuse "HOME is unset or not a directory"
user=$(id -un)
if command -v getent >/dev/null 2>&1; then
  real_home=$(getent passwd "$user" | cut -d: -f6)
elif command -v dscl >/dev/null 2>&1; then
  real_home=$(dscl . -read "/Users/$user" NFSHomeDirectory | awk '{print $2}')
else
  refuse "cannot look up the account's real home to compare against"
fi
[[ -n "$real_home" ]] || refuse "the account's real home did not resolve"
[[ "$(cd "$HOME" && pwd -P)" != "$(cd "$real_home" && pwd -P)" ]] || refuse "HOME is the account's real home: $HOME"

d="$HOME/.claude"
f="$d/settings.json"
[[ ! -e "$f" ]] || refuse "$f already exists"
mkdir -p "$d"
cat >"$f" <<'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "bash -c 'echo \"$(git branch --show-current) (dev)\"'",
    "padding": 2
  }
}
JSON
cg="$d/context-usage"
mkdir -p "$cg"
[[ ! -e "$cg/cache-line.mjs" ]] || refuse "$cg/cache-line.mjs already exists"
cp "$(dirname "${BASH_SOURCE[0]}")/../../scripts/cache-line.mjs" "$cg/cache-line.mjs"
