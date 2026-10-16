#!/usr/bin/env bash
# The SessionStart row that names /guardrails:setup apply install-git-hooks when this clone
# lacks the guardrails git-hook entries: run as hooks.json declares it, in a fresh clone,
# with the option off, and with every entry declined.
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

# The row's argv, with the plugin root put in as Claude Code does.
row_args() {
  jq -r '.hooks.SessionStart[].hooks[] | select(.command == "node" and (.args | index("GIT_HOOKS_NOTICE_ENABLED"))) | .args[]' \
    "$ROOT/hooks/hooks.json" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$ROOT#g"
}

args=()
while IFS= read -r a; do args+=("$a"); done < <(row_args)
expect "hooks.json carries the git-hooks notice row" yes "$([[ ${#args[@]} -gt 0 ]] && echo yes)"

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
expect "the option off keeps the row quiet" "" "$(run_row CLAUDE_PLUGIN_OPTION_GIT_HOOKS_NOTICE_ENABLED=false)"

for e in $(jq -r '.entries[].name' "$ROOT/git-hooks/entries.json"); do
  node "$ROOT/lib/git-hooks/install.mjs" decline --entry "$e" --repo "$REPO" --plugin-root "$ROOT" >/dev/null 2>&1
done
expect "the decline recorded its per-clone key" true \
  "$(git -C "$REPO" config --local --get checks.guardrails.pre-commit-content.declined)"
expect "every entry declined keeps the row quiet" "" "$(run_row)"

echo "git-hooks-notice: $PASS passed, $FAIL failed"
((FAIL == 0))
