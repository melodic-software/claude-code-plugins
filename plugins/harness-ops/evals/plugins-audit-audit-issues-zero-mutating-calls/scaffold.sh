#!/usr/bin/env bash
# Seeds a fixture fleet in the run's home: one marketplace, one plugin behind its catalog, one current, one new.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
home="${EVAL_FIXTURE_HOME:-$(cd .. && pwd)}"
p="$home/.claude/plugins"
m="$p/marketplaces/fixture-market"
mkdir -p "$m/.claude-plugin" "$p/cache"
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
printf '{"enabledPlugins":{"alpha@fixture-market":true,"beta@fixture-market":true,"harness-ops@fixture-market":true}}\n' >"$home/.claude/settings.json"
mkdir -p "$PWD/.claude"
for f in "$home/.claude/settings.local.json" "$PWD/.claude/settings.local.json" "$PWD/.claude/settings.json"; do [[ -s "$f" ]] || printf "{}\n" >"$f"; done
