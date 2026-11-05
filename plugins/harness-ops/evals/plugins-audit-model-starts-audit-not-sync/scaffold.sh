#!/usr/bin/env bash
# Seeds a fixture fleet in the run's home: one marketplace, one plugin behind its catalog, one current, one new.
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

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
p="$HOME/.claude/plugins"
m="$p/marketplaces/fixture-market"
targets=("$p/known_marketplaces.json" "$p/installed_plugins.json" "$HOME/.claude/settings.json"
  "$HOME/.claude/settings.local.json" "$PWD/.claude/settings.local.json" "$PWD/.claude/settings.json")
for f in "${targets[@]}" "$m"; do [[ ! -e "$f" ]] || refuse "$f already exists"; done

mkdir -p "$m/.claude-plugin" "$p/cache" "$PWD/.claude"
for spec in alpha:2.0.0 beta:1.0.0 gamma:1.0.0 harness-ops:0.0.0; do
  n=${spec%%:*}
  v=${spec##*:}
  mkdir -p "$m/$n/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$n" "$v" >"$m/$n/.claude-plugin/plugin.json"
done
cat >"$m/.claude-plugin/marketplace.json" <<'JSON'
{"name":"fixture-market","owner":{"name":"fixture"},"plugins":[
{"name":"alpha","source":"./alpha"},
{"name":"beta","source":"./beta"},
{"name":"gamma","source":"./gamma"},
{"name":"harness-ops","source":"./harness-ops"}]}
JSON
cat >"$p/known_marketplaces.json" <<JSON
{"fixture-market":{"source":{"source":"github","repo":"fixture/market"},"installLocation":"$m","lastUpdated":"2026-11-01T00:00:00.000Z","autoUpdate":false}}
JSON
cat >"$p/installed_plugins.json" <<JSON
{"version":2,"plugins":{
"alpha@fixture-market":[{"scope":"user","installPath":"$p/cache/fixture-market/alpha/1.0.0","version":"1.0.0","installedAt":"2026-10-01T00:00:00.000Z","lastUpdated":"2026-10-01T00:00:00.000Z"}],
"beta@fixture-market":[{"scope":"user","installPath":"$p/cache/fixture-market/beta/1.0.0","version":"1.0.0","installedAt":"2026-10-01T00:00:00.000Z","lastUpdated":"2026-10-01T00:00:00.000Z"}],
"harness-ops@fixture-market":[{"scope":"user","installPath":"$root","version":"0.0.0","installedAt":"2026-10-01T00:00:00.000Z","lastUpdated":"2026-10-01T00:00:00.000Z"}]}}
JSON
printf '{"enabledPlugins":{"alpha@fixture-market":true,"beta@fixture-market":true,"harness-ops@fixture-market":true}}\n' >"$HOME/.claude/settings.json"
for f in "$HOME/.claude/settings.local.json" "$PWD/.claude/settings.local.json" "$PWD/.claude/settings.json"; do printf '{}\n' >"$f"; done
