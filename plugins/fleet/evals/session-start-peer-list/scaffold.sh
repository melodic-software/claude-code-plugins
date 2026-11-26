#!/usr/bin/env bash
# The runner sets HOME to the run's temporary home: https://code.claude.com/docs/en/plugin-evals#seed-the-workspace-or-conversation
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
real_home=$(cd "$real_home" && pwd -P)
home=$(cd "$HOME" && pwd -P)
[[ "$home" != "$real_home" ]] || refuse "HOME is the account's real home: $HOME"
[[ "$(pwd -P)" != "$real_home" ]] || refuse "the working directory is the account's real home: $PWD"

if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  os=windows kind=wsl
elif [[ "$(uname -s)" == Darwin ]]; then
  os=macos kind=macos
else
  os=linux kind=linux
fi

stub="$home/.local/bin/claude"
manifest="$home/.config/fleet/fleet.json"
for f in "$stub" "$manifest"; do
  [[ ! -e "$f" ]] || refuse "$f already exists"
done
mkdir -p "${stub%/*}" "${manifest%/*}"

cat >"$stub" <<'SH'
#!/bin/sh
id=$(printf '%s' "${CLAUDE_CODE_SESSION_ID:-unset}" | cut -c1-8)
printf '[{"sessionId":"0f1e2d3c-0000-4000-8000-00000000peer","cwd":"/srv/scratch","kind":"interactive","status":"idle","name":"fleet-peer-%s","startedAt":%s000}]\n' "$id" "$(($(date +%s) - 600))"
SH
chmod +x "$stub"

cat >"$manifest" <<JSON
{
  "version": 1,
  "self": "eval-host",
  "hosts": [
    { "key": "eval-host", "os": "$os", "role": "server", "lanes": [ { "kind": "$kind", "route": "local", "claudePath": "$stub" } ] }
  ]
}
JSON
