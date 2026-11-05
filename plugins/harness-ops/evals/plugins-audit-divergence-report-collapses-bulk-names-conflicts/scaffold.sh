#!/usr/bin/env bash
# Seeds the fleet the divergence case names: 29 plugins whose project and user scopes differ, 2 same-version multi-scope, 1 settings-only delisted id.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
home="${EVAL_FIXTURE_HOME:-$(cd .. && pwd)}"
cwd="${EVAL_FIXTURE_CWD:-$PWD}"
p="$home/.claude/plugins"
m="$p/marketplaces/fixture-market"
mkdir -p "$m/.claude-plugin" "$p/cache" "$cwd/.claude" "$home/other-project/.claude"
git -C "$cwd" init -q 2>/dev/null || true
git -C "$home/other-project" init -q
installed=""
catalog=""
enabled=""
rec() { # id scope version [projectPath]
  local extra=""
  [[ -z "${4:-}" ]] || extra=",\"projectPath\":\"$4\""
  printf '{"scope":"%s"%s,"installPath":"%s/cache/fixture-market/%s/%s","version":"%s","installedAt":"2026-10-01T00:00:00.000Z","lastUpdated":"2026-10-01T00:00:00.000Z"}' "$2" "$extra" "$p" "${1%@*}" "$3" "$3"
}
add() { # name user-version project-version
  local n=$1 id="$1@fixture-market"
  mkdir -p "$m/$n/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$n" "${4:-$2}" >"$m/$n/.claude-plugin/plugin.json"
  catalog+="${catalog:+,}{\"name\":\"$n\",\"source\":\"./$n\"}"
  installed+="${installed:+,}\"$id\":[$(rec "$id" user "$2"),$(rec "$id" project "$3" "$home/other-project")]"
  enabled+="${enabled:+,}\"$id\":true"
}
for i in $(seq -w 1 29); do add "skew$i" 1.0.0 2.0.0; done
add same1 1.0.0 1.0.0
add same2 1.0.0 1.0.0
mkdir -p "$m/harness-ops/.claude-plugin"
printf '{"name":"harness-ops","version":"0.0.0"}\n' >"$m/harness-ops/.claude-plugin/plugin.json"
catalog+=',{"name":"harness-ops","source":"./harness-ops"}'
enabled+=",\"gone@fixture-market\":true,\"harness-ops@fixture-market\":true"
printf '{"name":"fixture-market","owner":{"name":"fixture"},"plugins":[%s]}\n' "$catalog" >"$m/.claude-plugin/marketplace.json"
printf '{"fixture-market":{"source":{"source":"github","repo":"fixture/market"},"installLocation":"%s","lastUpdated":"2026-11-01T00:00:00.000Z","autoUpdate":false}}\n' "$m" >"$p/known_marketplaces.json"
installed+=",\"harness-ops@fixture-market\":[{\"scope\":\"user\",\"installPath\":\"$root\",\"version\":\"0.0.0\",\"installedAt\":\"2026-10-01T00:00:00.000Z\",\"lastUpdated\":\"2026-10-01T00:00:00.000Z\"}]"
printf '{"version":2,"plugins":{%s}}\n' "$installed" >"$p/installed_plugins.json"
printf '{"enabledPlugins":{%s}}\n' "$enabled" >"$home/.claude/settings.json"
mkdir -p "$PWD/.claude"
for f in "$home/.claude/settings.local.json" "$PWD/.claude/settings.local.json" "$PWD/.claude/settings.json"; do [[ -s "$f" ]] || printf "{}\n" >"$f"; done
