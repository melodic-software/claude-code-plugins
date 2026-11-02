#!/usr/bin/env bash
# The SessionStart probe that names /guardrails:setup apply install-git-hooks when this clone
# lacks the guardrails git-hook entries: run as harness-ops' prerequisites-fleet.mjs runs it
# (this plugin's own lib/prerequisites.mjs probe), in a fresh clone and with every entry
# declined. The runner skips it while the session_probe option is off; its own test covers that.
# test-scope: plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/prerequisites.json plugins/guardrails/lib/prerequisites.mjs plugins/guardrails/hooks/hooks.json
# test-scope: plugins/guardrails/git-hooks/commit-msg-convention.sh plugins/guardrails/git-hooks/pre-commit-content.sh plugins/guardrails/git-hooks/reference-verify.sh
# test-scope: plugins/guardrails/hooks/abort-boundary.sh plugins/guardrails/hooks/cli-flag-verify.sh plugins/guardrails/hooks/hook-utils.sh plugins/guardrails/hooks/resolve-convention-pattern.sh
# test-scope: plugins/guardrails/hooks/run-guards.sh plugins/guardrails/hooks/skill-reference-verify.sh plugins/guardrails/hooks/stale-path-verify.sh plugins/guardrails/lib/git-hooks/check-lib.sh
# test-scope: plugins/guardrails/lib/path-detection/hardcoded-path-patterns.sh plugins/guardrails/lib/path-detection/machine-path-patterns.sh
# test-scope: plugins/guardrails/lib/secret-detection/secret-patterns.sh plugins/guardrails/lib/verification/cli-flag-cache.sh plugins/guardrails/lib/verification/verify-cli-flag.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HERE="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

expect "prerequisites.json opts into the session probe behind GIT_HOOKS_NOTICE_ENABLED" GIT_HOOKS_NOTICE_ENABLED \
  "$(jq -r '.session_probe.run_if_unset_or_true' "$ROOT/prerequisites.json" | tr -d '\r')"
args=("$ROOT/lib/prerequisites.mjs" probe "$ROOT")

REPO="$WORK/repo"
git init -q -b main "$REPO"
n=0
run_row() { # [ENV=value ...] -> the row's stdout
  n=$((n + 1))
  ((${#args[@]})) || return 0
  printf '{"session_id":"s%d"}' "$n" |
    env CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_DATA="$WORK/data" "$@" node "${args[@]}" 2>/dev/null
}

out="$(run_row)"
expect "a clone without the entries is told how to install them" yes \
  "$(grep -qF '/guardrails:setup apply install-git-hooks' <<<"$out" && echo yes)"

for e in $(jq -r '.entries[].name' "$ROOT/git-hooks/entries.json"); do
  node "$ROOT/lib/git-hooks/install.mjs" decline --entry "$e" --repo "$REPO" --plugin-root "$ROOT" >/dev/null 2>&1
done
expect "the decline recorded its per-clone key" true \
  "$(git -C "$REPO" config --local --get checks.guardrails.pre-commit-content.declined)"
expect "every entry declined keeps the row quiet" "" "$(run_row)"

echo "git-hooks-notice: $PASS passed, $FAIL failed"
((FAIL == 0))
