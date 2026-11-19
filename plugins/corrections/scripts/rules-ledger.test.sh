#!/usr/bin/env bash
# Tests for rules-ledger.mjs: a complete ledger passes, and each way a rule can be dropped or left
# unaccounted for fails with a line naming it.
# test-scope: plugins/corrections/*
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER_SCRIPT="$SCRIPT_DIR/rules-ledger.mjs"
LADDER="$SCRIPT_DIR/../skills/codify/reference/enforcement-ladder.md"

# shellcheck source=../lib/test-helpers.sh
source "$SCRIPT_DIR/../lib/test-helpers.sh"

for tool in node jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "1..0 # SKIP $tool not available"
    exit 0
  fi
done

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
R="$TEST_TMPDIR/repo"
mkdir -p "$R/.claude/rules"
cat >"$R/AGENTS.md" <<'EOF'
# Project

Never import from `src/internal/` outside that folder.
Write names a reader understands without the
surrounding code.
Run tests with `npm test`.
See `.claude/rules/api.md` for the API rules.
EOF
cat >"$R/.claude/rules/api.md" <<'EOF'
Every handler returns a typed result.
EOF

# A complete ledger: one row per disposition, each with the fields it needs.
cat >"$TEST_TMPDIR/good.json" <<'EOF'
{
  "inputs": [
    { "file": "AGENTS.md", "rules": 3 },
    { "file": ".claude/rules/api.md", "rules": 1 }
  ],
  "rows": [
    { "source": "AGENTS.md:3", "rule": "Never import from `src/internal/` outside that folder.",
      "disposition": "check", "rung": "architecture-test", "check": "npm run lint:boundaries",
      "old_ref": "abc123", "proof_exit": 0, "covers": ["src/app.ts importing src/internal/db"],
      "prose": "flag-delete" },
    { "source": "AGENTS.md:4", "rule": "Write names a reader understands without the surrounding code.",
      "disposition": "prose", "reason": "needs judgment" },
    { "source": "AGENTS.md:6", "rule": "Run tests with `npm test`.",
      "disposition": "delete", "reason": "package.json scripts.test states it" },
    { "source": ".claude/rules/api.md:1", "rule": "Every handler returns a typed result.",
      "disposition": "held", "reason": "unproven: no commit ever broke it, so no old ref" }
  ]
}
EOF

# run <ledger>: the script from inside the repository; stdout to $OUT, stderr to $ERR.
run() {
  (cd "$R" && node "$LEDGER_SCRIPT" "$@") >"$TEST_TMPDIR/out" 2>"$TEST_TMPDIR/err"
  RC=$?
  OUT="$(cat "$TEST_TMPDIR/out")"
  ERR="$(cat "$TEST_TMPDIR/err")"
}
# variant <name> <jq filter>: writes good.json transformed by the filter and sets V to its path.
variant() {
  V="$TEST_TMPDIR/$1.json"
  jq "$2" "$TEST_TMPDIR/good.json" >"$V"
}
# fails_with <name> <pattern>: the last run exited 1 and stderr matches the pattern.
fails_with() {
  DETAIL="exit $RC; stderr: $ERR"
  check "$1: exits 1" test "$RC" -eq 1
  DETAIL="stderr: $ERR"
  check "$1: stderr names it" grep -qE "$2" <<<"$ERR"
}

# 1. A complete ledger passes and prints the tally per file.
run "$TEST_TMPDIR/good.json"
DETAIL="exit $RC; out: $OUT; stderr: $ERR"
check "complete ledger: exits 0" test "$RC" -eq 0
DETAIL="out: $OUT"
check "complete ledger: tallies each file" grep -qx 'AGENTS.md: 3 rules: 1 check, 1 prose, 1 delete, 0 held' <<<"$OUT"
DETAIL="out: $OUT"
check "complete ledger: says every rule is accounted for" grep -qx 'ledger complete: 4 rules from 2 files accounted for' <<<"$OUT"

# 2. A rule dropped silently: the file declares more rules than it has rows.
variant dropped 'del(.rows[1])'
run "$V"
fails_with "dropped rule" 'AGENTS\.md: declares 3 rules, ledger has 2 rows'

# 3. An input file with no count, and one with zero rules and no reason.
variant nocount 'del(.inputs[1].rules)'
run "$V"
fails_with "no rule count" '\.claude/rules/api\.md: no rule count'
variant zero '.inputs[1].rules = 0 | del(.rows[3])'
run "$V"
fails_with "zero rules, no reason" '\.claude/rules/api\.md: declares 0 rules with no reason'
variant zeroreason '.inputs[1].rules = 0 | .inputs[1].reason = "only a pointer" | del(.rows[3])'
run "$V"
DETAIL="exit $RC; stderr: $ERR"
check "zero rules with a reason: exits 0" test "$RC" -eq 0

# 4. A row whose file is not an input, or whose source is not file:line.
variant stray '.rows[1].source = "README.md:1"'
run "$V"
fails_with "row from a file not read" 'README\.md:1: not one of the input files'
variant badsource '.rows[1].source = "AGENTS.md"'
run "$V"
fails_with "source without a line" 'AGENTS\.md: source is not <file>:<line>'

# 5. The quoted rule must be in the file at that line.
variant fabricated '.rows[1].rule = "Use tabs."'
run "$V"
fails_with "rule not at its line" 'AGENTS\.md:4: rule text not found at that line'
variant moved '.rows[1].source = "AGENTS.md:6"'
run "$V"
fails_with "rule at the wrong line" 'AGENTS\.md:6: rule text not found at that line'

# 6. A disposition outside the four.
variant fifth '.rows[1].disposition = "maybe"'
run "$V"
fails_with "unknown disposition" 'AGENTS\.md:4: disposition "maybe" is not check, prose, delete or held'
variant none 'del(.rows[1].disposition)'
run "$V"
fails_with "missing disposition" 'AGENTS\.md:4: disposition (missing|"undefined")'

# 7. A check row needs a rung, a proof that held, the known cases and the prose flagged.
variant norung 'del(.rows[0].rung)'
run "$V"
fails_with "check without rung" 'AGENTS\.md:3: check row has no rung'
variant guidance '.rows[0].rung = "instruction"'
run "$V"
fails_with "check on a guidance rung" 'AGENTS\.md:3: rung "instruction" is not a checking rung'
variant alias '.rows[0].rung = "semgrep-rule"'
run "$V"
fails_with "check under an old rung id" 'rung "semgrep-rule" is an old id: write "syntax-pattern-rule"'
variant unproven '.rows[0].proof_exit = 1'
run "$V"
fails_with "check whose proof did not hold" 'AGENTS\.md:3: proof exit 1, not 0: an unproven check is held'
variant noproof 'del(.rows[0].proof_exit) | del(.rows[0].old_ref)'
run "$V"
fails_with "check with no proof" 'AGENTS\.md:3: check row has no old_ref'
variant nocovers '.rows[0].covers = []'
run "$V"
fails_with "check with no known cases" 'AGENTS\.md:3: check row lists no known cases it covers'
variant prosekept 'del(.rows[0].prose)'
run "$V"
fails_with "check with prose left beside it" 'AGENTS\.md:3: check row does not flag its prose for deletion'

variant planted 'del(.rows[0].old_ref) | .rows[0].plant = ".work/codify/x/plant-1.patch"'
run "$V"
DETAIL="exit $RC; stderr: $ERR"
check "check proven by a plant: exits 0" test "$RC" -eq 0
variant bothproofs '.rows[0].plant = ".work/codify/x/plant-1.patch"'
run "$V"
fails_with "check with an old ref and a plant" 'AGENTS\.md:3: check row has both old_ref and plant'

variant fmt '.rows[0].rung = "formatter" | .rows[0].style = "formatter" | .rows[1].style = "lint"'
run "$V"
DETAIL="exit $RC; stderr: $ERR"
check "formatter and lint labels: exits 0" test "$RC" -eq 0
variant fmtnolabel '.rows[0].rung = "formatter"'
run "$V"
fails_with "formatter rung without its label" 'AGENTS\.md:3: formatter rung row needs style "formatter"'
variant fmtwrongrung '.rows[0].style = "formatter"'
run "$V"
fails_with "formatter label on a lint rung" 'AGENTS\.md:3: style "formatter" needs the formatter rung'
variant badstyle '.rows[3].style = "pretty"'
run "$V"
fails_with "unknown style label" 'api\.md:1: style "pretty" is not formatter or lint'

# 8. A prose, delete or held row needs a reason.
for i in 1 2 3; do
  variant "noreason$i" "del(.rows[$i].reason)"
  run "$V"
  DETAIL="exit $RC; stderr: $ERR"
  check "row $i without a reason: exits 1" test "$RC" -eq 1
  DETAIL="stderr: $ERR"
  check "row $i without a reason: stderr names it" grep -q 'row has no reason' <<<"$ERR"
done

# 9. The same rule listed twice.
variant twice '.rows += [.rows[1]] | .inputs[0].rules = 4'
run "$V"
fails_with "rule listed twice" 'AGENTS\.md:4: listed twice'

# 9b. One rule cannot stand in for the rule on the line above it.
printf 'Use descriptive names.\nNever log secrets.\n' >"$R/TWO.md"
cat >"$TEST_TMPDIR/standin.json" <<'EOF'
{
  "inputs": [{ "file": "TWO.md", "rules": 2 }],
  "rows": [
    { "source": "TWO.md:1", "rule": "Never log secrets.", "disposition": "prose", "reason": "x" },
    { "source": "TWO.md:2", "rule": "Never log secrets.", "disposition": "prose", "reason": "x" }
  ]
}
EOF
run "$TEST_TMPDIR/standin.json"
fails_with "quote from the next line" 'TWO\.md:1: rule text not found at that line'

# 10. Usage and unreadable input.
run
DETAIL="exit $RC; stderr: $ERR"
check "no argument: exits 2" test "$RC" -eq 2
run "$TEST_TMPDIR/missing.json"
DETAIL="exit $RC; stderr: $ERR"
check "missing ledger: exits 2" test "$RC" -eq 2
printf 'not json' >"$TEST_TMPDIR/bad.json"
run "$TEST_TMPDIR/bad.json"
DETAIL="exit $RC; stderr: $ERR"
check "ledger that is not JSON: exits 2" test "$RC" -eq 2

# 11. Every checking rung id the script accepts is a rung id in the ladder copy.
for id in $(node "$LEDGER_SCRIPT" --list-rungs); do
  DETAIL="rung $id"
  check "rung $id is in the ladder" grep -q "\`$id\`" "$LADDER"
done

printf '1..%d\n' "$CASE_NUM"
if [[ $FAILED -gt 0 ]]; then
  echo "# $FAILED of $CASE_NUM failed"
  exit 1
fi
