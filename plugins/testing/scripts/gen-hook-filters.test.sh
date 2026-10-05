#!/usr/bin/env bash
# Test for gen-hook-filters.sh: the shipped hooks.json is in sync with the
# adapters, every row is gated by an `if`, no row matches a non-test path, no
# glob repeats, and --check catches drift.
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

check "PostToolUse Write|Edit runs test-scan and test-judge-bg, PreToolUse runs test-weaken" \
  '[[ "$(jq -r "[.hooks.PostToolUse[] | select(.matcher == \"Write|Edit\") | .hooks[].args[-1] | sub(\".*/\"; \"\")] | unique | join(\" \")" "$HOOKS")" == "test-judge-bg.sh test-scan.sh" &&
    "$(jq -r "[.hooks.PreToolUse[].hooks[].args[-1]] | unique | join(\" \")" "$HOOKS")" == */test-weaken.sh ]]'

# The judge rows: the background job on the same `if` rows as test-scan,
# async; one Stop and one SubagentStop entry at timeout 240; one SessionStart
# entry. Every judge row is gated on both options.
judge() { jq -r "$1" "$HOOKS"; }
check "test-judge-bg rows are async and match test-scan's if rows" \
  '[[ "$(judge "[.hooks.PostToolUse[].hooks[] | select(.args[-1] | endswith(\"/test-judge-bg.sh\")) | .async] | unique | tostring")" == "[true]" &&
    "$(judge "[.hooks.PostToolUse[].hooks[] | select(.args[-1] | endswith(\"/test-judge-bg.sh\")) | .if] | sort | tostring")" == "$(judge "[.hooks.PostToolUse[].hooks[] | select(.args[-1] | endswith(\"/test-scan.sh\")) | .if] | sort | tostring")" ]]'
check "Stop: one entry, test-judge.sh, timeout 240" \
  '[[ "$(judge ".hooks.Stop | length")" == 1 && "$(judge ".hooks.Stop[0].hooks | length")" == 1 &&
    "$(judge ".hooks.Stop[0].hooks[0].args[-1]")" == */test-judge.sh && "$(judge ".hooks.Stop[0].hooks[0].timeout")" == 240 ]]'
check "SubagentStop: one entry, the Stop hook's test-judge.sh, timeout 240" \
  '[[ "$(judge ".hooks.SubagentStop | length")" == 1 && "$(judge ".hooks.SubagentStop[0].hooks | length")" == 1 &&
    "$(judge ".hooks.SubagentStop[0].hooks[0].args[-1]")" == */test-judge.sh && "$(judge ".hooks.SubagentStop[0].hooks[0].timeout")" == 240 ]]'
check "SessionStart: the judge entry first, test-judge-start.sh, then the node-notice entry" \
  '[[ "$(judge ".hooks.SessionStart | length")" == 2 && "$(judge ".hooks.SessionStart[1].hooks[0].command | contains(\"node-notice /testing:check\")")" == true && "$(judge ".hooks.SessionStart[0].hooks[0].args[-1]")" == */test-judge-start.sh ]]'
check "every judge row is gated on test_guards_enabled and test_judge_enabled" \
  '[[ "$(judge "[(.hooks.PostToolUse[].hooks[] | select(.args[-1] | endswith(\"/test-judge-bg.sh\"))), .hooks.Stop[].hooks[], .hooks.SubagentStop[].hooks[], .hooks.SessionStart[0].hooks[]
      | .args[1:5] == [\"--require-true\", \"TEST_GUARDS_ENABLED\", \"--require-true\", \"TEST_JUDGE_ENABLED\"]] | unique | tostring")" == "[true]" ]]'
check "the description names both options" \
  '[[ "$(judge .description)" == *test_guards_enabled* && "$(judge .description)" == *test_judge_enabled* ]]'

check "PostToolUse has one Bash row, behind the same option gate, running test-scan-bash.sh" \
  '[[ "$(jq -r "[.hooks.PostToolUse[] | select(.matcher == \"Bash\") | .hooks[] | .args[1:] | join(\" \")] | join(\"|\")" "$HOOKS")" == "--require-true TEST_GUARDS_ENABLED "*/test-scan-bash.sh ]]'
check "PreToolUse has no Bash row" '[[ "$(jq "[.hooks.PreToolUse[] | select(.matcher | test(\"Bash\"))] | length" "$HOOKS")" == 0 ]]'

for event in PostToolUse PreToolUse; do
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
done

backup="$(mktemp)"
trap 'cp "$backup" "$HOOKS"; rm -f "$backup"' EXIT
cp "$HOOKS" "$backup"
jq '.hooks.PostToolUse[0].hooks |= .[1:]' "$backup" >"$HOOKS"
check "--check exits 1 on drift" '! bash "$GEN" --check 2>/dev/null'
bash "$GEN"
check "a regenerate restores sync" 'cmp -s "$HOOKS" "$backup"'

echo
echo "$PASS passed, $FAIL failed"
((FAIL == 0))
