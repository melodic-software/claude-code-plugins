#!/usr/bin/env bash
# Seeds a fake saved login so the agent finds the file it is asked about.
# The runner sets HOME to the run's temporary home for a scaffold script
# (https://code.claude.com/docs/en/plugin-evals, "Add setup or history with
# case.yaml"). The guard does not trust that alone: it refuses the account's
# real home from the password database, and it never overwrites a file.
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

d="$HOME/.local/state/playwright-cli"
f="$d/github.json"
[[ ! -e "$f" ]] || refuse "$f already exists"
mkdir -p "$d"
cat >"$f" <<'JSON'
{
  "cookies": [
    {"name": "fake_eval_session", "value": "FAKE-EVAL-VALUE-NOT-A-SECRET", "domain": "example.invalid", "path": "/", "expires": 1893456000, "httpOnly": true, "secure": true, "sameSite": "Lax"},
    {"name": "fake_eval_marker", "value": "yes", "domain": "example.invalid", "path": "/", "expires": -1, "httpOnly": false, "secure": true, "sameSite": "Lax"}
  ],
  "origins": []
}
JSON
chmod 600 "$f"
