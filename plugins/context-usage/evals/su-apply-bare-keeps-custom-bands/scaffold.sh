#!/usr/bin/env bash
# A fully valid zones.json with custom bands and one key the plugin does not
# recognize, so a bare apply has nothing to repair (setup SKILL.md apply step 2).
# The runner sets HOME to the run's temporary home for a scaffold script
# (https://code.claude.com/docs/en/plugin-evals, "Set up fixtures and mocks").
# The guard refuses the account's real home and never overwrites a file.
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

d="$HOME/.claude/context-usage"
f="$d/zones.json"
[[ ! -e "$f" ]] || refuse "$f already exists"
mkdir -p "$d"
cat >"$f" <<'JSON'
{
  "light_max_used_percentage": 40,
  "moderate_max_used_percentage": 70,
  "token_bands": {
    "200000": { "light_max_tokens": 90000, "moderate_max_tokens": 140000 },
    "1000000": { "light_max_tokens": 120000, "moderate_max_tokens": 450000 }
  },
  "display_color": "teal"
}
JSON
