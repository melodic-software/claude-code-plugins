#!/usr/bin/env bash
# A feature branch with an uncommitted half-change to a retry loop, a test script and no remote,
# so a handoff has real in-flight state to save. The run's home holds a user-scope install record
# for a stub plugin-profiles plugin (fixture-market, with a profile skill), and the project
# settings switch it off, so no plugin-profiles skill is listed: what a session sees when that
# plugin is installed but disabled. A gate that asks only whether the plugin is installed finds
# the install record and calls the skill, which the graders catch.
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

p="$HOME/.claude/plugins"
m="$p/marketplaces/fixture-market"
c="$p/cache/fixture-market/plugin-profiles/1.0.0"
for f in "$p/known_marketplaces.json" "$p/installed_plugins.json" "$m" "$c" "$PWD/.claude/settings.json"; do
  [[ ! -e "$f" ]] || refuse "$f already exists"
done

for d in "$m/plugin-profiles" "$c"; do
  mkdir -p "$d/.claude-plugin" "$d/skills/profile"
  printf '{"name":"plugin-profiles","version":"1.0.0"}\n' >"$d/.claude-plugin/plugin.json"
  cat >"$d/skills/profile/SKILL.md" <<'EOF'
---
name: profile
description: Apply, list or report the status of a plugin profile.
---

Print `Plugin profile: none applied.` and stop.
EOF
done
mkdir -p "$m/.claude-plugin"
cat >"$m/.claude-plugin/marketplace.json" <<'JSON'
{"name":"fixture-market","owner":{"name":"fixture"},"plugins":[{"name":"plugin-profiles","source":"./plugin-profiles"}]}
JSON
cat >"$p/known_marketplaces.json" <<JSON
{"fixture-market":{"source":{"source":"github","repo":"fixture/market"},"installLocation":"$m","lastUpdated":"2026-11-01T00:00:00.000Z","autoUpdate":false}}
JSON
cat >"$p/installed_plugins.json" <<JSON
{"version":2,"plugins":{
"plugin-profiles@fixture-market":[{"scope":"user","installPath":"$c","version":"1.0.0","installedAt":"2026-10-01T00:00:00.000Z","lastUpdated":"2026-10-01T00:00:00.000Z"}]}}
JSON

mkdir -p .claude
printf '{"enabledPlugins":{"plugin-profiles@fixture-market":false}}\n' >.claude/settings.json

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src
cat >src/retry.ts <<'EOF'
export function delayFor(attempt: number): number {
  return 1000;
}
EOF
printf '#!/usr/bin/env bash\ngrep -q "2 \\*\\* attempt" src/retry.ts\n' >test.sh
chmod +x test.sh
git add src test.sh
git commit -q -m "feat: fixed retry delay"

git checkout -q -b feat/retry-backoff
cat >src/retry.ts <<'EOF'
export function delayFor(attempt: number): number {
  // next: cap at 30 seconds
  return 1000 * 2 ** attempt;
}
EOF
