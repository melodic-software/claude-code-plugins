#!/usr/bin/env bash
# Test for gen-hook-filters.sh: the shipped hooks.json is in sync with the
# adapters, every row is gated by an `if`, no row matches a non-test path, no
# glob repeats, no per-edit scan or judge row ships, and --check catches drift.
# test-scope: plugins/testing/skills/audit/adapters/*.yaml
# test-scope: plugins/testing/hooks/hooks.json
# shellcheck disable=SC2016  # check() evals its single-quoted condition
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$DIR/gen-hook-filters.sh"
HOOKS="$DIR/../hooks/hooks.json"

PASS=0
FAIL=0
check() {
  if eval "$2"; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1" >&2
    FAIL=$((FAIL + 1))
  fi
}

check "shipped hooks.json is in sync (--check exits 0)" 'bash "$GEN" --check'

check "PreToolUse runs only test-weaken" \
  '[[ "$(jq -r "[.hooks.PreToolUse[].hooks[].args[-1]] | unique | join(\" \")" "$HOOKS")" == */test-weaken.sh ]]'

# Report-only test findings come from /testing:audit on demand: no per-edit
# scan, no task-end judge, no Bash row.
check "no PostToolUse, Stop or SubagentStop entry" \
  '[[ "$(jq "[.hooks.PostToolUse, .hooks.Stop, .hooks.SubagentStop] | map(length) | add" "$HOOKS")" == 0 ]]'
check "no row runs test-scan or a test-judge script" \
  '! grep -qE "test-scan|test-judge" "$HOOKS"'
check "SessionStart holds only the node-notice entry" \
  '[[ "$(jq ".hooks.SessionStart | length" "$HOOKS")" == 1 && "$(jq -r ".hooks.SessionStart[0].hooks[0].command | contains(\"node-notice /testing:check\")" "$HOOKS")" == true ]]'
check "PreToolUse has no Bash row" '[[ "$(jq "[.hooks.PreToolUse[] | select(.matcher | test(\"Bash\"))] | length" "$HOOKS")" == 0 ]]'

event=PreToolUse
rows="$(jq -r --arg e "$event" '.hooks[$e][] | select(.matcher == "Write|Edit") | .hooks[] | .if // "MISSING"' "$HOOKS")"
check "$event: every row has an if" '[[ -n "$rows" && "$rows" != *MISSING* ]]'
check "$event: no glob appears twice for one script" \
  '[[ "$(jq -r --arg e "$event" ".hooks[\$e][].hooks[] | \"\(.args[-1]) \(.if)\"" "$HOOKS" | sort | uniq -d)" == "" ]]'

matches_source=""
while IFS= read -r row; do
  glob="${row#*(}"
  glob="${glob%)}"
  # shellcheck disable=SC2053  # the glob is the pattern
  [[ app.ts == $glob ]] && matches_source+="$row "
done <<<"$rows"
check "$event: no row matches src/app.ts, so a non-test path spawns nothing" '[[ -z "$matches_source" ]]'
check "$event: a real test name is covered for Write and Edit" 'grep -qF "Write(*.test.ts)" <<<"$rows" && grep -qF "Edit(*.test.ts)" <<<"$rows"'

backup="$(mktemp)"
trap 'cp "$backup" "$HOOKS"; rm -f "$backup"' EXIT
cp "$HOOKS" "$backup"
jq '.hooks.PreToolUse[0].hooks |= .[1:]' "$backup" >"$HOOKS"
check "--check exits 1 on drift" '! bash "$GEN" --check 2>/dev/null'
bash "$GEN"
check "a regenerate restores sync" 'cmp -s "$HOOKS" "$backup"'

echo
echo "$PASS passed, $FAIL failed"
((FAIL == 0))
