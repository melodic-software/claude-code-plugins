#!/usr/bin/env bash
# Regression tests for instruction-scan.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/instruction-scan.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

if ! command -v grep >/dev/null 2>&1; then
  echo "SKIP: grep not installed" >&2
  exit 0
fi

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: I6 bare prohibitions flagged -----------------------------------
I6F="$TEST_TMPDIR/i6.md"
cat >"$I6F" <<'EOF'
Never commit secrets to the repository.
Do not use bare Bash grants in auto mode.
Always run the tests before pushing.
EOF
rc=0
OUT=$(bash "$SCRIPT" "$I6F") || rc=$?
assert_exit "I6 scan exits 0 (advisory)" 0 "$rc"
assert_contains "flags 'Never' prohibition on line 1" "$OUT" "$I6F:1:I6"
assert_contains "flags 'Do not' prohibition on line 2" "$OUT" "$I6F:2:I6"
assert_not_contains "positive 'Always' instruction not flagged" "$OUT" ":3:I6"
assert_eq "two I6 candidates" "2" "$(bash "$SCRIPT" --count "$I6F")"

# --- Case 3: prohibition WITH rationale not flagged -------------------------
I6R="$TEST_TMPDIR/i6-rationale.md"
cat >"$I6R" <<'EOF'
Never force-push to main because it rewrites shared history.
Do not skip the lint step, since CI will reject the PR otherwise.
EOF
assert_eq "rationale-bearing prohibitions not flagged" "0" "$(bash "$SCRIPT" --count "$I6R")"

# --- Case 4: I10 reasoning-echo directives flagged --------------------------
I10F="$TEST_TMPDIR/i10.md"
cat >"$I10F" <<'EOF'
Show your thinking before giving the final answer.
Explain your reasoning step by step in the response.
Think out loud as you work through the problem.
Summarize the changes in two bullet points.
EOF
OUT=$(bash "$SCRIPT" "$I10F")
assert_contains "flags 'Show your thinking'" "$OUT" "$I10F:1:I10"
assert_contains "flags 'Explain your reasoning'" "$OUT" "$I10F:2:I10"
assert_contains "flags 'Think out loud'" "$OUT" "$I10F:3:I10"
assert_not_contains "benign summarize instruction not flagged" "$OUT" ":4:I10"
assert_eq "three I10 candidates" "3" "$(bash "$SCRIPT" --count "$I10F")"

# --- Case 5: clean file ------------------------------------------------------
CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
Use ES modules syntax.
Run npm test before committing.
API handlers live in src/api/handlers/.
EOF
assert_contains "clean file message" "$(bash "$SCRIPT" "$CLEAN")" "No instruction candidates found."
assert_eq "clean file count is 0" "0" "$(bash "$SCRIPT" --count "$CLEAN")"

# --- Case 6: multiple files aggregate ---------------------------------------
assert_eq "aggregate count across files" "5" "$(bash "$SCRIPT" --count "$I6F" "$I10F")"

# --- Case 7: nonexistent path skipped, not an error -------------------------
rc=0
OUT=$(bash "$SCRIPT" "$TEST_TMPDIR/does-not-exist.md") || rc=$?
assert_exit "nonexistent path exits 0" 0 "$rc"
assert_contains "nonexistent path yields clean message" "$OUT" "No instruction candidates found."

# --- Case 8: no file arguments ----------------------------------------------
rc=0
OUT=$(bash "$SCRIPT") || rc=$?
assert_exit "no-args exits 0" 0 "$rc"
assert_eq "no-args count is 0" "0" "$(bash "$SCRIPT" --count)"

# --- Case 9: I8-a instructed self-check directives flagged -------------------
I8SC="$TEST_TMPDIR/i8-selfcheck.md"
cat >"$I8SC" <<'EOF'
Double-check your answer before responding.
Re-verify the output before you finish.
Include a final verification step for any non-trivial task.
Use a subagent to verify your work.
Verify your own work once more at the end.
Run the linter when you finish editing.
Double check the totals against the source table.
The results must be re-verified at the end.
Have a subagent verify the output.
EOF
OUT=$(bash "$SCRIPT" "$I8SC")
assert_contains "flags 'double-check your answer'" "$OUT" "$I8SC:1:I8-a"
assert_contains "flags 're-verify'" "$OUT" "$I8SC:2:I8-a"
assert_contains "flags 'final verification step'" "$OUT" "$I8SC:3:I8-a"
assert_contains "flags 'subagent to verify'" "$OUT" "$I8SC:4:I8-a"
assert_contains "flags 'verify your own work'" "$OUT" "$I8SC:5:I8-a"
assert_not_contains "benign lint instruction not flagged as I8-a" "$OUT" ":6:I8-a"
assert_contains "flags spaced 'double check'" "$OUT" "$I8SC:7:I8-a"
assert_contains "flags inflected 're-verified'" "$OUT" "$I8SC:8:I8-a"
assert_contains "flags 'have a subagent verify'" "$OUT" "$I8SC:9:I8-a"

# --- Case 10: I8-c don't-think directives flagged ----------------------------
I8DT="$TEST_TMPDIR/i8-dontthink.md"
cat >"$I8DT" <<'EOF'
Do not think before answering.
Don't reason about the request, answer directly.
Answer without thinking or reasoning.
Skip the reasoning and respond immediately.
Think carefully about the edge cases.
Don’t think about it, just answer.
EOF
OUT=$(bash "$SCRIPT" "$I8DT")
assert_contains "flags 'do not think'" "$OUT" "$I8DT:1:I8-c"
assert_contains "flags 'don't reason'" "$OUT" "$I8DT:2:I8-c"
assert_contains "flags 'without thinking'" "$OUT" "$I8DT:3:I8-c"
assert_contains "flags 'skip the reasoning'" "$OUT" "$I8DT:4:I8-c"
assert_not_contains "positive think instruction not flagged as I8-c" "$OUT" ":5:I8-c"
assert_contains "flags curly-apostrophe 'Don’t think'" "$OUT" "$I8DT:6:I8-c"

# --- Case 11: I8-b conservative-reporting directives flagged -----------------
I8CV="$TEST_TMPDIR/i8-conservative.md"
cat >"$I8CV" <<'EOF'
Be conservative in what you report.
Only report high-severity issues.
Don't nitpick minor style problems.
Report every finding with a severity label.
Report only the high-severity findings.
Do not nitpick.
Don’t nitpick style.
Only report critical-severity regressions.
EOF
OUT=$(bash "$SCRIPT" "$I8CV")
assert_contains "flags 'be conservative'" "$OUT" "$I8CV:1:I8-b"
assert_contains "flags 'only report high-severity'" "$OUT" "$I8CV:2:I8-b"
assert_contains "flags 'don't nitpick'" "$OUT" "$I8CV:3:I8-b"
assert_not_contains "report-everything instruction not flagged as I8-b" "$OUT" ":4:I8-b"
assert_contains "flags 'report only the high-severity'" "$OUT" "$I8CV:5:I8-b"
assert_contains "flags 'do not nitpick'" "$OUT" "$I8CV:6:I8-b"
assert_contains "flags curly-apostrophe 'Don’t nitpick'" "$OUT" "$I8CV:7:I8-b"
assert_contains "flags 'only report critical-severity'" "$OUT" "$I8CV:8:I8-b"

# --- Case 12: advisory over-production — restraint-clause text still emitted -
# The criteria fence (restraint-clause shape, quoted/meta surfaces) is owned by
# criteria.md and adjudicated by the model lane; the scanner deliberately
# over-produces, so tidyings-like "When NOT to apply" text IS a candidate row.
I8FP="$TEST_TMPDIR/i8-fence-shape.md"
cat >"$I8FP" <<'EOF'
When NOT to apply this tidying: be conservative here and skip the change.
EOF
OUT=$(bash "$SCRIPT" "$I8FP")
assert_contains "restraint-clause text still emitted (advisory contract)" "$OUT" "$I8FP:1:I8-b"

# --- Case 13: I23 self-estimated context-budget phrasing flagged -------------
I23F="$TEST_TMPDIR/i23.md"
cat >"$I23F" <<'EOF'
Invoke this skill mid-task when context is heavy.
Hand off once you are running low on context.
Check the remaining context before starting a new phase.
Consult /context output and decide whether to fork.
Beyond the final third of the window, write a handoff instead.
Stop when you are approaching the context limit.
Fork when the user reports the session is heavy.
Never stop on your own estimate of the remaining context.
EOF
OUT=$(bash "$SCRIPT" "$I23F")
assert_contains "flags 'context is heavy'" "$OUT" "$I23F:1:I23"
assert_contains "flags 'running low on context'" "$OUT" "$I23F:2:I23"
assert_contains "flags 'remaining context'" "$OUT" "$I23F:3:I23"
assert_contains "flags '/context output'" "$OUT" "$I23F:4:I23"
assert_contains "flags 'final third of the window'" "$OUT" "$I23F:5:I23"
assert_contains "flags 'approaching the context limit'" "$OUT" "$I23F:6:I23"
assert_not_contains "a licensed trigger naming no budget is not an I23 row" "$OUT" ":7:I23"
# Advisory over-production, same contract as Case 12: the counter-steer states
# the budget phrase in order to forbid acting on it, and the scanner cannot see
# polarity. criteria.md's inverted-polarity exemption is the model lane's.
assert_contains "counter-steer text still emitted (advisory contract)" "$OUT" "$I23F:8:I23"

# --- Case 14: I23 is not anchored to the bare term "context window" ----------
# Matching it would return every surface that discusses sessions at all, which
# is a corpus rather than a candidate set.
I23N="$TEST_TMPDIR/i23-neutral.md"
cat >"$I23N" <<'EOF'
The subagent runs with its own context window and sees none of this conversation.
Compaction replaces the conversation history with a summary.
EOF
OUT=$(bash "$SCRIPT" "$I23N")
assert_not_contains "bare 'context window' is not an I23 row" "$OUT" ":1:I23"
assert_not_contains "compaction prose is not an I23 row" "$OUT" ":2:I23"

# --- Case 15: I27 effort-for-brevity candidates ------------------------------
I27F="$TEST_TMPDIR/i27.md"
cat >"$I27F" <<'EOF'
Lower the effort level to keep responses short.
Reduce effort so replies stay concise.
Drop your effort setting for less verbose output.
Reduce effort to cut thinking cost on mechanical work.
Keep responses short and skimmable.
Decreasing effort trims response length.
Lower effort for brief answers.
Reduce the effort so output stays terse.
Lower your effort to avoid wordy replies.
Keep replies short by dropping effort.
Dropped effort keeps output brief.
This setting reduces effort to keep answers short.
The flag lowers effort for briefer output.
It drops effort to stay concise.
EOF
OUT=$(bash "$SCRIPT" "$I27F")
assert_contains "flags 'lower the effort … short'" "$OUT" "$I27F:1:I27"
assert_contains "flags 'reduce effort … concise'" "$OUT" "$I27F:2:I27"
assert_contains "flags 'drop your effort … verbose'" "$OUT" "$I27F:3:I27"
assert_not_contains "cost-ground effort lowering not flagged" "$OUT" ":4:I27"
assert_not_contains "brevity alone not flagged" "$OUT" ":5:I27"
assert_contains "flags inflected 'decreasing effort … length'" "$OUT" "$I27F:6:I27"
assert_contains "flags 'lower effort … brief'" "$OUT" "$I27F:7:I27"
assert_contains "flags 'reduce the effort … terse'" "$OUT" "$I27F:8:I27"
assert_contains "flags 'lower your effort … wordy'" "$OUT" "$I27F:9:I27"
assert_contains "flags doubled-p 'dropping effort … short'" "$OUT" "$I27F:10:I27"
assert_contains "flags doubled-p 'Dropped effort … brief'" "$OUT" "$I27F:11:I27"
assert_contains "flags third-person 'reduces effort … short'" "$OUT" "$I27F:12:I27"
assert_contains "flags third-person 'lowers effort … briefer'" "$OUT" "$I27F:13:I27"
assert_contains "flags third-person 'drops effort … concise'" "$OUT" "$I27F:14:I27"

# --- Case 16: --body-only fences YAML frontmatter -----------------------------
# The fence exists because check-skill.sh check 3 hard-FAILs a dropped
# `'trigger phrase'` versus the base ref: a row pointing at a description or a
# when_to_use invites a remediation that is an auto-invocation regression. It is
# opt-in, so the default path must keep reporting frontmatter.
FMF="$TEST_TMPDIR/frontmatter.md"
cat >"$FMF" <<'EOF'
---
description: "CRITICAL: audit things. You MUST run this."
when_to_use: "if in doubt, use this skill"
---

CRITICAL: run the linter first.
Default to using the seam.
EOF
rc=0
OUT=$(bash "$SCRIPT" "$FMF") || rc=$?
assert_exit "default mode exits 0 on a frontmatter file" 0 "$rc"
assert_contains "default mode still reports the description line" "$OUT" "$FMF:2:I28-a"
assert_contains "default mode still reports the when_to_use line" "$OUT" "$FMF:3:I28-b"
rc=0
OUT=$(bash "$SCRIPT" --body-only "$FMF") || rc=$?
assert_exit "--body-only exits 0" 0 "$rc"
assert_not_contains "--body-only drops the description line" "$OUT" "$FMF:2:"
assert_not_contains "--body-only drops the when_to_use line" "$OUT" "$FMF:3:"
assert_contains "--body-only keeps the body emphasis line" "$OUT" "$FMF:6:I28-a"
assert_contains "--body-only keeps the body blanket-default line" "$OUT" "$FMF:7:I28-b"
OUT=$(bash "$SCRIPT" --count --body-only "$FMF")
assert_eq "--count composes with --body-only" "2" "$OUT"
OUT=$(bash "$SCRIPT" --body-only --count "$FMF")
assert_eq "flag order does not matter" "2" "$OUT"

# A file with no frontmatter must be unaffected by the fence.
NOFM="$TEST_TMPDIR/nofrontmatter.md"
cat >"$NOFM" <<'EOF'
CRITICAL: run the linter first.
EOF
OUT=$(bash "$SCRIPT" --body-only "$NOFM")
assert_contains "--body-only is a no-op without frontmatter" "$OUT" "$NOFM:1:I28-a"

# A `---` that is a thematic break, not frontmatter, opens no block.
BREAKF="$TEST_TMPDIR/thematic.md"
cat >"$BREAKF" <<'EOF'
# Heading

---

CRITICAL: run the linter first.
EOF
OUT=$(bash "$SCRIPT" --body-only "$BREAKF")
assert_contains "a mid-document --- is not frontmatter" "$OUT" "$BREAKF:5:I28-a"

# An UNCLOSED leading `---` fences the whole file: fail-safe, since the
# alternative routes a malformed-frontmatter description to an apply relay.
UNCLOSED="$TEST_TMPDIR/unclosed.md"
cat >"$UNCLOSED" <<'EOF'
---
description: "IMPORTANT: x"
CRITICAL: never terminated
EOF
OUT=$(bash "$SCRIPT" --body-only "$UNCLOSED")
assert_not_contains "unclosed frontmatter fences the whole file" "$OUT" "$UNCLOSED:"
OUT=$(bash "$SCRIPT" "$UNCLOSED")
assert_contains "unclosed frontmatter still reports in default mode" "$OUT" "$UNCLOSED:2:I28-a"

# --- Case 17: CRLF files do not defeat the fence -----------------------------
# `head`/`awk` leave a terminal CR, so a CRLF delimiter reads as "---\r" and
# matched neither frontmatter test: the block was treated as body and the
# description and when_to_use lines became candidates. The fence inverted on
# exactly the Windows-authored files it most needs to hold for.
CRLFF="$TEST_TMPDIR/crlf.md"
printf -- '---\r\ndescription: "CRITICAL: you MUST not edit this."\r\nwhen_to_use: "if in doubt, use this"\r\n---\r\n\r\nCRITICAL: run the linter.\r\n' >"$CRLFF"
OUT=$(bash "$SCRIPT" --body-only "$CRLFF")
assert_not_contains "CRLF: description line is fenced" "$OUT" "$CRLFF:2:"
assert_not_contains "CRLF: when_to_use line is fenced" "$OUT" "$CRLFF:3:"
assert_contains "CRLF: the body line is still a candidate" "$OUT" "$CRLFF:6:I28-a"
OUT=$(bash "$SCRIPT" "$CRLFF")
assert_contains "CRLF: default mode still reports the description" "$OUT" "$CRLFF:2:I28-a"

# A CRLF file with an UNCLOSED leading `---` must still fence the whole file.
CRLFU="$TEST_TMPDIR/crlf-unclosed.md"
printf -- '---\r\ndescription: "IMPORTANT: x"\r\nCRITICAL: never terminated\r\n' >"$CRLFU"
OUT=$(bash "$SCRIPT" --body-only "$CRLFU")
assert_not_contains "CRLF: unclosed frontmatter fences the whole file" "$OUT" "$CRLFU:"

# --- Case 18: missing grep exits 2 -------------------------------------------
real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" "$CLEAN" 2>&1) || rc=$?
assert_exit "exit 2 when grep missing" 2 "$rc"
assert_contains "grep required message" "$err_out" "grep required"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
