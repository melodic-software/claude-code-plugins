#!/usr/bin/env bash
# Test for gen-hook-filters.sh: the shipped hooks.json is in sync with the
# adapters, every row is gated by an `if`, no row matches a non-test path, no
# glob repeats, and --check catches drift.
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

check "PostToolUse Write|Edit runs test-scan, PreToolUse runs test-weaken" \
  '[[ "$(jq -r "[.hooks.PostToolUse[] | select(.matcher == \"Write|Edit\") | .hooks[].args[-1]] | unique | join(\" \")" "$HOOKS")" == */test-scan.sh &&
    "$(jq -r "[.hooks.PreToolUse[].hooks[].args[-1]] | unique | join(\" \")" "$HOOKS")" == */test-weaken.sh ]]'

check "PostToolUse has one Bash row, behind the same option gate, running test-scan-bash.sh" \
  '[[ "$(jq -r "[.hooks.PostToolUse[] | select(.matcher == \"Bash\") | .hooks[] | .args[1:] | join(\" \")] | join(\"|\")" "$HOOKS")" == "--require-true TEST_GUARDS_ENABLED "*/test-scan-bash.sh ]]'
check "PreToolUse has no Bash row" '[[ "$(jq "[.hooks.PreToolUse[] | select(.matcher | test(\"Bash\"))] | length" "$HOOKS")" == 0 ]]'

for event in PostToolUse PreToolUse; do
  rows="$(jq -r --arg e "$event" '.hooks[$e][] | select(.matcher == "Write|Edit") | .hooks[] | .if // "MISSING"' "$HOOKS")"
  check "$event: every row has an if" '[[ -n "$rows" && "$rows" != *MISSING* ]]'
  check "$event: no glob appears twice" '[[ "$(sort <<<"$rows" | uniq -d)" == "" ]]'

  matches_source=""
  while IFS= read -r row; do
    glob="${row#*(}"
    glob="${glob%)}"
    # shellcheck disable=SC2053  # the glob is the pattern
    [[ app.ts == $glob ]] && matches_source+="$row "
  done <<<"$rows"
  check "$event: no row matches src/app.ts, so a non-test path spawns nothing" '[[ -z "$matches_source" ]]'
  check "$event: a real test name is covered for Write and Edit" 'grep -qF "Write(*.test.ts)" <<<"$rows" && grep -qF "Edit(*.test.ts)" <<<"$rows"'
done

backup="$(mktemp)"
cp "$HOOKS" "$backup"
jq '.hooks.PostToolUse[0].hooks |= .[1:]' "$backup" >"$HOOKS"
check "--check exits 1 on drift" '! bash "$GEN" --check 2>/dev/null'
bash "$GEN"
check "a regenerate restores sync" 'cmp -s "$HOOKS" "$backup"'
cp "$backup" "$HOOKS"
rm -f "$backup"

echo
echo "$PASS passed, $FAIL failed"
((FAIL == 0))
