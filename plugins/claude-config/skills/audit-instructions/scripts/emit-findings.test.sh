#!/usr/bin/env bash
# Regression tests for emit-findings.sh (assertions from test-helpers.sh beside
# this file; both ship with the plugin).
#
# The body-scope cases are the load-bearing ones: check-skill.sh check 3 hard-FAILs
# a dropped `'trigger phrase'` versus the base ref, so a finding whose remediation
# edits a description, when_to_use, or a quoted trigger phrase is an
# auto-invocation regression. Those cases assert the WRITER's own fence, fed
# deliberately-unfenced input, because a fence that lives only in the caller is
# one caller away from being bypassed.
set -uo pipefail

# Fixture git isolation: this suite builds a throwaway repository (case 9c), and
# `git -C` is a readability guard, not isolation — an inherited ABSOLUTE GIT_DIR
# overrides repository discovery outright and GIT_CONFIG redirects what `git
# config` writes, so the fixture identity would land in the CALLER's .git/config,
# shared by every worktree of the clone. Cleared unconditionally, before any
# fixture command. Case 3b's per-command `GIT_DIR=...` prefix is unaffected: it
# scopes to that one invocation and is set deliberately, not inherited.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$SCRIPT_DIR/emit-findings.sh"
SCAN="$SCRIPT_DIR/instruction-scan.sh"
FIXTURES="$(cd "$SCRIPT_DIR/../evals/fixtures" && pwd)"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

if ! command -v grep >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
  echo "SKIP: grep and awk required" >&2
  exit 0
fi

emit() { # emit <scan-file> <out> -> stdout of the written file
  bash "$EMIT" --from "$1" --out "$2" --branch testbranch >/dev/null 2>&1
  cat "$2" 2>/dev/null
}

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$EMIT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: usage errors ----------------------------------------------------
rc=0
bash "$EMIT" >/dev/null 2>&1 || rc=$?
assert_exit "no args exits 2" 2 "$rc"
rc=0
bash "$EMIT" --from /nonexistent/x --out "$TEST_TMPDIR/o.md" >/dev/null 2>&1 || rc=$?
assert_exit "missing --from file exits 2" 2 "$rc"
rc=0
bash "$EMIT" --from "$FIXTURES/protected-content.md" --out "$TEST_TMPDIR/o.md" --bogus >/dev/null 2>&1 || rc=$?
assert_exit "unknown argument exits 2" 2 "$rc"

# --- Case 3: non-scanner input refused (exit 3) ------------------------------
# --branch is passed explicitly so this case isolates the scanner-row check.
# Without it the branch default runs first, and on a DETACHED HEAD — which is
# exactly what a CI checkout of a PR merge ref gives you — that default resolves
# to empty and exits 2, masking the condition under test. Case 3b below asserts
# that exit-2 path on purpose instead of tripping over it here.
NOTSCAN="$TEST_TMPDIR/notscan.txt"
printf 'this is not scanner output\nneither is this\n' >"$NOTSCAN"
rc=0
bash "$EMIT" --from "$NOTSCAN" --out "$TEST_TMPDIR/o3.md" --branch testbranch >/dev/null 2>&1 || rc=$?
assert_exit "input with no scan rows exits 3" 3 "$rc"
if [[ -e "$TEST_TMPDIR/o3.md" ]]; then
  fail "refused input writes no file" "o3.md was created"
else
  pass "refused input writes no file"
fi

# --- Case 3b: no resolvable branch refuses rather than guessing --------------
# `branch:` is load-bearing for the consumer: fix-pass-mode.md "Step 1" admits a
# candidate only when its branch: equals the current branch EXACTLY. With no
# current branch there is nothing correct to write, so the script must refuse
# rather than emit a file the relay can never match. GIT_DIR is pointed at a
# nonexistent path so `git branch --show-current` cannot resolve one, which is
# the hermetic stand-in for CI's detached-HEAD checkout of a PR merge ref.
bash "$SCAN" --body-only "$FIXTURES/frontmatter-emphasis.md" >"$TEST_TMPDIR/nb.txt"
rc=0
GIT_DIR="$TEST_TMPDIR/no-such-git-dir" bash "$EMIT" \
  --from "$TEST_TMPDIR/nb.txt" --out "$TEST_TMPDIR/nb.md" >/dev/null 2>&1 || rc=$?
assert_exit "no --branch and no current branch exits 2" 2 "$rc"
if [[ -e "$TEST_TMPDIR/nb.md" ]]; then
  fail "an unresolvable branch writes no file" "nb.md was created"
else
  pass "an unresolvable branch writes no file"
fi
rc=0
GIT_DIR="$TEST_TMPDIR/no-such-git-dir" bash "$EMIT" \
  --from "$TEST_TMPDIR/nb.txt" --out "$TEST_TMPDIR/nb2.md" --branch explicit >/dev/null 2>&1 || rc=$?
assert_exit "an explicit --branch works with no git branch" 0 "$rc"
assert_contains "the explicit branch is what gets written" "$(cat "$TEST_TMPDIR/nb2.md")" "branch: explicit"

# --- Case 4: conforming frontmatter ------------------------------------------
bash "$SCAN" --body-only "$FIXTURES/frontmatter-emphasis.md" >"$TEST_TMPDIR/fm.txt"
OUT=$(emit "$TEST_TMPDIR/fm.txt" "$TEST_TMPDIR/fm.md")
assert_contains "declares type: review-findings" "$OUT" "type: review-findings"
assert_contains "carries the branch it was told" "$OUT" "branch: testbranch"
assert_contains "carries a ## Findings section" "$OUT" "## Findings"
assert_contains "carries a ## Surfaces section" "$OUT" "## Surfaces"
DATE_LINE=$(printf '%s\n' "$OUT" | grep '^date:')
if printf '%s\n' "$DATE_LINE" | grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
  pass "date: is a full ISO-8601 UTC instant the consumer can parse"
else
  fail "date: is a full ISO-8601 UTC instant the consumer can parse" "got: $DATE_LINE"
fi

# --- Case 5: BODY-SCOPE FENCE (negative test, the container hard constraint) --
# Feed the writer DELIBERATELY UNFENCED scan output. Its own fence must decline
# every frontmatter row, so no emitted remediation can touch a description or a
# when_to_use.
bash "$SCAN" "$FIXTURES/frontmatter-emphasis.md" >"$TEST_TMPDIR/unfenced.txt"
assert_contains "unfenced input really does carry frontmatter rows" \
  "$(cat "$TEST_TMPDIR/unfenced.txt")" "frontmatter-emphasis.md:2:I28-a"
OUT=$(emit "$TEST_TMPDIR/unfenced.txt" "$TEST_TMPDIR/unfenced.md")
ROWS=$(printf '%s\n' "$OUT" | grep -c '^| [0-9]')
assert_eq "unfenced input still emits only the 2 body rows" "2" "$ROWS"
assert_not_contains "no emitted row points at the description line" "$OUT" "frontmatter-emphasis.md:2"
assert_not_contains "no emitted row points at the when_to_use line" "$OUT" "frontmatter-emphasis.md:3"
assert_contains "frontmatter declines are reported, never silent" "$OUT" "reason=frontmatter (body-scope fence)"

# --- Case 6: quoted-trigger-phrase fence -------------------------------------
bash "$SCAN" --body-only "$FIXTURES/quoted-trigger.md" >"$TEST_TMPDIR/qt.txt"
OUT=$(emit "$TEST_TMPDIR/qt.txt" "$TEST_TMPDIR/qt.md")
assert_not_contains "a body line quoting a description trigger phrase is not emitted" \
  "$OUT" "quoted-trigger.md:7"
assert_contains "a body line with no quoted trigger phrase still emits" "$OUT" "quoted-trigger.md:8"
assert_contains "trigger-phrase declines are reported, never silent" \
  "$OUT" "reason=quoted-trigger-phrase (body-scope fence)"

# --- Case 7: protected content produces no I28 row ---------------------------
# One line per protected category named by the container spec. The scanner may
# mark other families on this file; none may reach the findings file, because
# none of them has a severity-crosswalk row.
bash "$SCAN" --body-only "$FIXTURES/protected-content.md" >"$TEST_TMPDIR/pc.txt"
assert_not_contains "no I28 candidate on any protected-content line" \
  "$(cat "$TEST_TMPDIR/pc.txt")" "I28"
# The scanner may now return no row at all for this file, and the emitter
# refuses an empty scan, so a non-crosswalk row keeps the coverage path under test.
grep -v '^No instruction candidates' "$TEST_TMPDIR/pc.txt" >"$TEST_TMPDIR/pc-rows.txt" || true
printf '%s\n' "$FIXTURES/protected-content.md:1:I6" >>"$TEST_TMPDIR/pc-rows.txt"
OUT=$(emit "$TEST_TMPDIR/pc-rows.txt" "$TEST_TMPDIR/pc.md")
ROWS=$(printf '%s\n' "$OUT" | grep -c '^| [0-9]')
assert_eq "protected content emits zero findings" "0" "$ROWS"
assert_contains "a zero-finding run still writes coverage" "$OUT" "## Surfaces"
assert_contains "both rules reported as returning no result" "$OUT" "Returned no result:"

# --- Case 8: only crosswalk-backed rules are emitted -------------------------
# I6/I8/I10/I23/I25/I27 have no severity-crosswalk row, so the contract admits no
# row for them; they must be counted as declined rather than dropped.
MIXED="$TEST_TMPDIR/mixed.txt"
{
  printf '%s\n' "$FIXTURES/quoted-trigger.md:8:I28-a"
  printf '%s\n' "$FIXTURES/quoted-trigger.md:8:I6"
  printf '%s\n' "$FIXTURES/quoted-trigger.md:8:I23"
} >"$MIXED"
OUT=$(emit "$MIXED" "$TEST_TMPDIR/mixed.md")
ROWS=$(printf '%s\n' "$OUT" | grep -c '^| [0-9]')
assert_eq "only the I28 row is emitted from a mixed input" "1" "$ROWS"
assert_contains "non-crosswalk families are declined with a reason" \
  "$OUT" "reason=no-severity-crosswalk-row"

# --- Case 8b: a row pointing past EOF is declined, not emitted blank ---------
# Sits with Case 8 because both decide which rows are ADMITTED versus declined.
# The scan output and the source file are read at different moments: the model
# lane edits the --from file to drop carve-out rows, and a source file touched in
# that window (or a stale scan-output file reused) leaves a row whose line number
# no longer exists. source_line() then returns "", and the row must become a
# COUNTED decline rather than a finding with an empty excerpt. This assertion
# pins that fail-safe direction against an off-by-one in source_line's
# counting loop silently changing it.
# Uses its own output variable: `OUT` is read by later cases (10, 11) that expect
# the downgrade fixture's output, and clobbering it would make those cases assert
# against this empty run instead.
EOFROW="$TEST_TMPDIR/past-eof.txt"
printf '%s\n' "$FIXTURES/frontmatter-emphasis.md:9999:I28-a" >"$EOFROW"
EOF_OUT=$(emit "$EOFROW" "$TEST_TMPDIR/past-eof.md")
EOF_ROWS=$(printf '%s\n' "$EOF_OUT" | grep -c '^| [0-9]')
assert_eq "a scan row past EOF emits no findings row" "0" "$EOF_ROWS"
assert_contains "the unreadable-source decline is counted, never silent" \
  "$EOF_OUT" "reason=source-line-unreadable"
assert_not_contains "no row is emitted with an empty excerpt" "$EOF_OUT" "frontmatter-emphasis.md:9999"

# --- Case 8c: unmatched --from lines are counted, never silent (#3279) ------
# Count first, classify second: I28-z (well-formed except suffix outside
# [a-f]), prose, and a blank increment Scan rows read and land in
# reason=unparsable-row. I100-a still matches and declines as
# no-severity-crosswalk-row; I28-a still emits.
UNPARSABLE="$TEST_TMPDIR/unparsable.txt"
{
  printf '%s\n' "$FIXTURES/quoted-trigger.md:8:I28-a"
  printf '%s\n' "$FIXTURES/quoted-trigger.md:8:I28-z"
  printf '%s\n' "this is not a scan row"
  printf '\n'
  printf '%s\n' "$FIXTURES/quoted-trigger.md:8:I100-a"
} >"$UNPARSABLE"
UNP_OUT=$(emit "$UNPARSABLE" "$TEST_TMPDIR/unparsable.md")
UNP_ROWS=$(printf '%s\n' "$UNP_OUT" | grep -c '^| [0-9]')
assert_eq "I28-a still emits from a mixed unparsable input" "1" "$UNP_ROWS"
assert_contains "I28-a is the emitted Location" "$UNP_OUT" "quoted-trigger.md:8"
assert_contains "Scan rows read counts every considered line, including unparsable" \
  "$UNP_OUT" "Scan rows read: 5. Emitted: 1."
assert_contains "I28-z is a counted decline, not dropped" \
  "$UNP_OUT" "Declined candidates: I28-z count=1 reason=unparsable-row"
assert_contains "prose and blank lines share the unparsable-row bucket" \
  "$UNP_OUT" "Declined candidates: (unparsable) count=2 reason=unparsable-row"
assert_contains "I100-a still declines as no-severity-crosswalk-row" \
  "$UNP_OUT" "Declined candidates: I100-a count=1 reason=no-severity-crosswalk-row"

# A CRLF-terminated matching row is parsed, not dropped. The intake pattern
# must strip CR before anchoring on $, or a CR-terminated I28-a vanishes.
CRLF_ROW="$TEST_TMPDIR/crlf-row.txt"
printf '%s\r\n' "$FIXTURES/quoted-trigger.md:8:I28-a" >"$CRLF_ROW"
CRLF_ROW_OUT=$(emit "$CRLF_ROW" "$TEST_TMPDIR/crlf-row.md")
assert_contains "a CRLF-terminated matching row is parsed, not dropped" \
  "$CRLF_ROW_OUT" "quoted-trigger.md:8"
assert_contains "and the CRLF row is counted as read and emitted" \
  "$CRLF_ROW_OUT" "Scan rows read: 1. Emitted: 1."
assert_not_contains "a matching CRLF row is not declined as unparsable" \
  "$CRLF_ROW_OUT" "reason=unparsable-row"

# Mixed LF + CRLF: the CR row must not vanish from the count.
MIXCRLF="$TEST_TMPDIR/mix-crlf.txt"
{
  printf '%s\n' "$FIXTURES/quoted-trigger.md:8:I28-a"
  printf '%s\r\n' "$FIXTURES/quoted-trigger.md:8:I28-z"
} >"$MIXCRLF"
MIXCRLF_OUT=$(emit "$MIXCRLF" "$TEST_TMPDIR/mix-crlf.md")
assert_contains "a mixed CRLF file counts both lines" \
  "$MIXCRLF_OUT" "Scan rows read: 2. Emitted: 1."
assert_contains "the CRLF I28-z row is a counted decline" \
  "$MIXCRLF_OUT" "Declined candidates: I28-z count=1 reason=unparsable-row"

# --- Case 9: DOWNGRADE contract in the Action cell ---------------------------
# The remediation is a downgrade, never a deletion: the directive survives and
# only its volume changes. The byte-for-byte survival of a specific directive is
# proved end-to-end against the apply relay; what is mechanically checkable here
# is that no emitted Action instructs a deletion, and that both instruct survival.
bash "$SCAN" --body-only "$FIXTURES/frontmatter-emphasis.md" >"$TEST_TMPDIR/dg.txt"
OUT=$(emit "$TEST_TMPDIR/dg.txt" "$TEST_TMPDIR/dg.md")
assert_contains "coercive-emphasis Action names the downgrade, not a deletion" \
  "$OUT" "Downgrade the emphasis, never the directive"
assert_contains "coercive-emphasis Action requires the directive to survive" \
  "$OUT" "must survive the edit verbatim"
assert_contains "coercive-emphasis Action allows only the forced capitalization" \
  "$OUT" "apart from capitalization forced by dropping a leading wrapper"
assert_contains "blanket-default Action keeps the instruction" \
  "$OUT" "do not delete the instruction"
ACTIONS=$(printf '%s\n' "$OUT" | grep '^| [0-9]' | sed 's/.*| \(Downgrade\|Replace\)/\1/')
assert_not_contains "no Action instructs removing the instruction" "$ACTIONS" "Remove the instruction"
assert_not_contains "no Action instructs deleting the line" "$ACTIONS" "Delete the line"

# --- Case 9b: the downgrade actually preserves the directive ------------------
# Applies each Action to its own Location and asserts what survived. The strict
# byte-for-byte form is NOT achievable for a leading wrapper: dropping
# "CRITICAL: You MUST " promotes the next word to sentence-initial position, so
# one byte legitimately changes. The official source's own worked example makes
# the same change ("...MUST use this tool when" -> "Use this tool when"), so the
# contract asserts verbatim survival APART FROM that capitalization.
DG="$TEST_TMPDIR/downgrade.md"
cat >"$DG" <<'EOF'
---
description: "Fixture. Use when: 'downgrade demo'."
---

CRITICAL: You MUST resolve the item id before calling the seam.
EOF
ORIG_FM=$(sed -n '1,3p' "$DG")
# The remediation the Action cell specifies, applied by hand at Location.
REMEDIATED="Resolve the item id before calling the seam."
NEW_FM=$(sed -n '1,3p' "$DG")
assert_eq "frontmatter is untouched by a body remediation" "$ORIG_FM" "$NEW_FM"
ORIG_DIRECTIVE="resolve the item id before calling the seam."
assert_not_contains "the coercive wrapper is gone" "$REMEDIATED" "CRITICAL: You MUST"
# Case-insensitive comparison is the contract: only the forced capitalization differs.
if [[ "$(printf '%s' "$REMEDIATED" | tr '[:upper:]' '[:lower:]')" == "$ORIG_DIRECTIVE" ]]; then
  pass "the directive survives verbatim apart from forced capitalization"
else
  fail "the directive survives verbatim apart from forced capitalization" \
    "expected '$ORIG_DIRECTIVE', got '$(printf '%s' "$REMEDIATED" | tr '[:upper:]' '[:lower:]')'"
fi
# And the remediated line must no longer be a candidate: no stale finding survives
# its own remediation.
printf '%s\n' "$REMEDIATED" >"$TEST_TMPDIR/remediated.md"
POST=$(bash "$SCAN" --body-only "$TEST_TMPDIR/remediated.md")
assert_contains "the remediated line is no longer a candidate" "$POST" "No instruction candidates found."

# --- Case 9c: CRLF files do not defeat the body-scope fence ------------------
# Regression for a measured defect: awk getline leaves a terminal CR, so a CRLF
# delimiter reads as "---\r" and matched neither frontmatter test. The block was
# then treated as body and description/when_to_use rows became emittable — the
# fence silently inverted on exactly the Windows-authored files it most needs to
# hold for. The fixture lives inside a throwaway git repo so the out-of-repo
# fence (case 9d) does not mask what this case is measuring.
CRLFREPO="$TEST_TMPDIR/crlf-repo"
mkdir -p "$CRLFREPO"
git -C "$CRLFREPO" init -q 2>/dev/null
printf -- '---\r\ndescription: "CRITICAL: you MUST not edit this."\r\nwhen_to_use: "if in doubt, use this"\r\n---\r\n\r\nCRITICAL: run the linter.\r\n' >"$CRLFREPO/crlf.md"
SCAN_OUT=$(bash "$SCAN" --body-only "$CRLFREPO/crlf.md")
assert_not_contains "scanner fence holds on CRLF: no description row" "$SCAN_OUT" "crlf.md:2"
assert_not_contains "scanner fence holds on CRLF: no when_to_use row" "$SCAN_OUT" "crlf.md:3"
assert_contains "scanner still finds the CRLF body row" "$SCAN_OUT" "crlf.md:6:I28-a"
# Feed the writer DELIBERATELY UNFENCED CRLF input; its own fence must hold too.
bash "$SCAN" "$CRLFREPO/crlf.md" >"$TEST_TMPDIR/crlf-unfenced.txt"
(cd "$CRLFREPO" && bash "$EMIT" --from "$TEST_TMPDIR/crlf-unfenced.txt" \
  --out "$TEST_TMPDIR/crlf-find.md" --branch testbranch >/dev/null 2>&1)
CRLF_OUT=$(cat "$TEST_TMPDIR/crlf-find.md")
assert_not_contains "writer fence holds on CRLF: no description row" "$CRLF_OUT" "crlf.md:2"
assert_not_contains "writer fence holds on CRLF: no when_to_use row" "$CRLF_OUT" "crlf.md:3"
assert_contains "writer still emits the CRLF body row" "$CRLF_OUT" "crlf.md:6"
assert_not_contains "no stray CR survives into a table cell" "$CRLF_OUT" "$(printf '\r')"

# Trailing whitespace on the delimiter: real frontmatter to
# skill_frontmatter::extract (^---[[:space:]]*$), so the writer fence must agree.
# Exact "---" equality is stricter than the gate this fence exists to satisfy,
# and the mismatch runs the dangerous way — the block reads as body.
printf -- '---   \ndescription: "CRITICAL: you MUST not edit this."\nwhen_to_use: "if in doubt, use this"\n---\t\n\nCRITICAL: run the linter.\n' >"$CRLFREPO/ws.md"
bash "$SCAN" "$CRLFREPO/ws.md" >"$TEST_TMPDIR/ws-unfenced.txt"
(cd "$CRLFREPO" && bash "$EMIT" --from "$TEST_TMPDIR/ws-unfenced.txt" \
  --out "$TEST_TMPDIR/ws-find.md" --branch testbranch >/dev/null 2>&1)
WS_OUT=$(cat "$TEST_TMPDIR/ws-find.md")
assert_not_contains "writer fence holds on a trailing-space delimiter" "$WS_OUT" "ws.md:2"
assert_not_contains "writer fence holds on a trailing-tab delimiter" "$WS_OUT" "ws.md:3"
assert_contains "writer still emits the body row past a trailing-ws delimiter" "$WS_OUT" "ws.md:6"

# --- Case 9d: surfaces outside the repo never reach the relay ----------------
# Phase A inventories user-level surfaces under CLAUDE_CONFIG_DIR too, but
# Location is contractually repo-relative and the fix action fences each
# remediation to it. An absolute Location would have the fix pass either edit a
# file outside the working tree or consume the finding without applying it.
OUTSIDE="$TEST_TMPDIR/fakehome"
mkdir -p "$OUTSIDE"
printf -- '# User CLAUDE.md\n\nCRITICAL: You MUST always do this.\n' >"$OUTSIDE/CLAUDE.md"
bash "$SCAN" --body-only "$OUTSIDE/CLAUDE.md" >"$TEST_TMPDIR/outside.txt"
assert_contains "the scanner does mark the user-level hit" \
  "$(cat "$TEST_TMPDIR/outside.txt")" "CLAUDE.md:3:I28-a"
(cd "$CRLFREPO" && bash "$EMIT" --from "$TEST_TMPDIR/outside.txt" \
  --out "$TEST_TMPDIR/outside-find.md" --branch testbranch >/dev/null 2>&1)
OUT_SIDE=$(cat "$TEST_TMPDIR/outside-find.md")
ROWS=$(printf '%s\n' "$OUT_SIDE" | grep -c '^| [0-9]')
assert_eq "an out-of-repo surface emits no findings row" "0" "$ROWS"
assert_not_contains "no absolute path reaches the findings file" "$OUT_SIDE" "$OUTSIDE"
assert_contains "the out-of-repo decline is counted, never silent" "$OUT_SIDE" "reason=outside-repo-root"

# --- Case 9e: branch names that are YAML indicators ---------------------------
# git accepts "@foo", "!foo", "#foo". Emitted as plain scalars, "#foo" reads as a
# comment and the others as YAML indicators, so the consumer — which admits a
# candidate only on an EXACT branch match — silently drops every finding for that
# branch. Quoting is conditional: an ordinary name must stay byte-identical.
bash "$SCAN" --body-only "$FIXTURES/frontmatter-emphasis.md" >"$TEST_TMPDIR/yb.txt"
for b in '@foo' '!foo' '#foo' '*foo' '&foo'; do
  bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/yb-out.md" --branch "$b" >/dev/null 2>&1
  LINE=$(grep '^branch:' "$TEST_TMPDIR/yb-out.md")
  assert_eq "branch '$b' is emitted as a quoted scalar" "branch: \"$b\"" "$LINE"
  rm -f "$TEST_TMPDIR/yb-out.md"
done
for b in 'main' 'feat/3120-thing' 'release-1.2_x'; do
  bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/yb-out.md" --branch "$b" >/dev/null 2>&1
  LINE=$(grep '^branch:' "$TEST_TMPDIR/yb-out.md")
  assert_eq "ordinary branch '$b' stays an unquoted plain scalar" "branch: $b" "$LINE"
  rm -f "$TEST_TMPDIR/yb-out.md"
done

# --- Case 9f: model-lane carve-out declines are counted ----------------------
# The model lane drops carve-out candidates before this script runs, so without
# a way to record them ## Surfaces would report fewer examined candidates than
# were actually looked at — a silent decline, which this producer forbids.
bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/co.md" \
  --branch testbranch --declined-carveout 3 >/dev/null 2>&1
assert_contains "a carve-out decline count is reported" \
  "$(cat "$TEST_TMPDIR/co.md")" "count=3 reason=criteria-carve-out"
assert_not_contains "omitting the flag reports no carve-out line" \
  "$(emit "$TEST_TMPDIR/yb.txt" "$TEST_TMPDIR/co2.md")" "criteria-carve-out"
rc=0
bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/co3.md" \
  --branch testbranch --declined-carveout notanumber >/dev/null 2>&1 || rc=$?
assert_exit "a non-numeric carve-out count exits 2" 2 "$rc"

# --- Case 9g: residency-unresolved holds are counted under their own reason --
# A RESIDENCY-UNRESOLVED row proposes no edit, so the lane holds it out of
# --from; the count keeps that decline visible without borrowing the I28
# carve-out label, which names a different ground.
bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/ru.md" \
  --branch testbranch --declined-residency 2 >/dev/null 2>&1
RU=$(cat "$TEST_TMPDIR/ru.md")
assert_contains "a residency-unresolved decline count is reported" \
  "$RU" "count=2 reason=residency-unresolved"
assert_not_contains "a residency hold is not reported as a carve-out" \
  "$RU" "criteria-carve-out"
assert_not_contains "omitting the flag reports no residency line" \
  "$(emit "$TEST_TMPDIR/yb.txt" "$TEST_TMPDIR/ru2.md")" "residency-unresolved"
rc=0
bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/ru3.md" \
  --branch testbranch --declined-residency two >/dev/null 2>&1 || rc=$?
assert_exit "a non-numeric residency count exits 2" 2 "$rc"

# --- Case 10: tier and confidence are rule-keyed, not per-finding ------------
TIERS=$(printf '%s\n' "$OUT" | grep '^| [0-9]' | awk -F'|' '{print $3}' | tr -d ' ' | sort -u)
assert_eq "every emitted row carries the crosswalk tier" "IMPORTANT" "$TIERS"
CONFS=$(printf '%s\n' "$OUT" | grep '^| [0-9]' | awk -F'|' '{print $4}' | tr -d ' ' | sort -u)
assert_eq "confidence is high, never low" "high" "$CONFS"

# --- Case 11: every Finding cell leads with the qualified rule id ------------
BAD=0
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  cell=$(printf '%s\n' "$row" | awk -F'|' '{print $7}' | sed 's/^ *//')
  case "$cell" in
  "claude-config/audit-instructions/rule-"*) ;;
  *) BAD=$((BAD + 1)) ;;
  esac
done < <(printf '%s\n' "$OUT" | grep '^| [0-9]')
assert_eq "every Finding cell leads with the qualified rule id" "0" "$BAD"
assert_contains "the fired condition carries the run's own value" "$OUT" 'marker="CRITICAL:"'

# --- Case 12: non-overwrite naming -------------------------------------------
bash "$EMIT" --from "$TEST_TMPDIR/dg.txt" --out "$TEST_TMPDIR/dup.md" --branch testbranch >/dev/null 2>&1
bash "$EMIT" --from "$TEST_TMPDIR/dg.txt" --out "$TEST_TMPDIR/dup.md" --branch testbranch >/dev/null 2>&1
if [[ -f "$TEST_TMPDIR/dup.md" && -f "$TEST_TMPDIR/dup-2.md" ]]; then
  pass "a second write takes the -2 suffix instead of clobbering"
else
  fail "a second write takes the -2 suffix instead of clobbering" "dup-2.md missing"
fi

# --- Case 13: cell escaping ---------------------------------------------------
# The fixture lives inside the throwaway repo from case 9c: the out-of-repo
# fence would otherwise decline it and this case would measure nothing.
PIPEF="$CRLFREPO/pipe.md"
# shellcheck disable=SC2016  # the backticks are literal markdown in the fixture, not a subshell
printf 'CRITICAL: run `a | b | c` before pushing.\n' >"$PIPEF"
bash "$SCAN" --body-only "$PIPEF" >"$TEST_TMPDIR/pipe.txt"
(cd "$CRLFREPO" && bash "$EMIT" --from "$TEST_TMPDIR/pipe.txt" \
  --out "$TEST_TMPDIR/pipe-out.md" --branch testbranch >/dev/null 2>&1)
OUT=$(cat "$TEST_TMPDIR/pipe-out.md")
ROW=$(printf '%s\n' "$OUT" | grep '^| [0-9]')
assert_contains "literal pipes in the excerpt are escaped" "$ROW" '\|'
# Count columns the way the consumer's markdown parse does: an escaped `\|` is a
# literal, not a delimiter, so strip the escapes before counting. Splitting on
# every `|` (as bare awk -F'|' does) would count them as separators and is
# precisely the misread the escaping exists to prevent.
COLS=$(printf '%s\n' "$ROW" | sed 's/\\|//g' | awk -F'|' '{print NF}')
assert_eq "an excerpt containing pipes still parses as one 7-column row" "9" "$COLS"

# --- Case 13b: cell escaping is idempotent -----------------------------------
# A naive gsub double-escapes a pipe the SOURCE already escaped (`a \| b` ->
# `a \\| b`), which GFM reads as a literal backslash plus a LIVE delimiter.
PIPEF2="$CRLFREPO/already-pipe.md"
# shellcheck disable=SC2016  # backticks and \| are fixture content, not a subshell
printf 'CRITICAL: run `a \| b` before pushing.\n' >"$PIPEF2"
# Feed a synthetic scan row whose excerpt (the source line) already contains \|.
printf '%s\n' "$PIPEF2:1:I28-a" >"$TEST_TMPDIR/already-pipe.txt"
(cd "$CRLFREPO" && bash "$EMIT" --from "$TEST_TMPDIR/already-pipe.txt" \
  --out "$TEST_TMPDIR/already-pipe-out.md" --branch testbranch >/dev/null 2>&1)
ALREADY_ROW=$(LC_ALL=C grep -m1 '^| [0-9]' "$TEST_TMPDIR/already-pipe-out.md")
assert_not_contains "an already-escaped pipe is not double-escaped" "$ALREADY_ROW" '\\\|'
assert_contains "and survives as a single-escaped literal" "$ALREADY_ROW" '\|'
ALREADY_COLS=$(printf '%s\n' "$ALREADY_ROW" | sed 's/\\|//g' | awk -F'|' '{print NF}')
assert_eq "so the row still parses as one 7-column row" "9" "$ALREADY_COLS"

# --- Case 13c: repo-root spelling mismatch does not fail-close an in-repo file
# This producer fails CLOSED: a path it cannot prove is under the root is
# declined. On Git Bash, git's toplevel and the caller's pwd can name the
# same directory differently; that mismatch must not decline in-repo hits.
# A symlink makes the two spellings disagree on Linux too.
SPELL_REAL="$TEST_TMPDIR/spell-real"
SPELL_LINK="$TEST_TMPDIR/spell-link"
mkdir -p "$SPELL_REAL"
git -C "$SPELL_REAL" init -q 2>/dev/null
printf -- '# Body\n\nCRITICAL: You MUST always do this.\n' >"$SPELL_REAL/doc.md"
ln -sfn "$SPELL_REAL" "$SPELL_LINK"
bash "$SCAN" --body-only "$SPELL_LINK/doc.md" >"$TEST_TMPDIR/spell.txt"
(cd "$SPELL_LINK" && bash "$EMIT" --from "$TEST_TMPDIR/spell.txt" \
  --out "$TEST_TMPDIR/spell-find.md" --branch testbranch >/dev/null 2>&1)
SPELL_OUT=$(cat "$TEST_TMPDIR/spell-find.md")
assert_contains "a pwd-spelled in-repo path is emitted, not declined" "$SPELL_OUT" "doc.md:3"
assert_not_contains "and is not counted as out-of-repo" "$SPELL_OUT" "reason=outside-repo-root"
assert_not_contains "Location carries no absolute prefix" "$SPELL_OUT" "$SPELL_LINK/doc.md"

# --- Case 13d: a repo-relative scan-row path is admitted; traversal is not ---
# instruction-scan.sh echoes the caller's own path form, so naming a repo-owned
# file relatively — the ordinary invocation, and the form SKILL.md documents —
# puts a relative path on the row. Declining those rows drops real findings from
# the relay while the run still reads as clean, which is the worst failure shape
# an audit tool has.
RELREPO="$TEST_TMPDIR/rel-repo"
mkdir -p "$RELREPO/sub"
git -C "$RELREPO" init -q
printf -- '# Body\n\nCRITICAL: You MUST always do this.\n' >"$RELREPO/doc.md"
printf -- '# Body\n\nCRITICAL: You MUST always do this.\n' >"$RELREPO/sub/nested.md"
printf -- '# Body\n\nCRITICAL: You MUST always do this.\n' >"$TEST_TMPDIR/outside-doc.md"

(cd "$RELREPO" && bash "$SCAN" --body-only doc.md) >"$TEST_TMPDIR/rel.txt"
assert_eq "the scanner emits the caller's relative path verbatim" \
  "doc.md:3:I28-a" "$(cat "$TEST_TMPDIR/rel.txt")"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/rel.txt" \
  --out "$TEST_TMPDIR/rel-find.md" --branch testbranch >/dev/null 2>&1)
REL_OUT=$(cat "$TEST_TMPDIR/rel-find.md")
assert_contains "a relative scan-row path is emitted, not declined" "$REL_OUT" "| doc.md:3 |"
assert_not_contains "and is not counted as out-of-repo" "$REL_OUT" "reason=outside-repo-root"
assert_contains "every scan row read survives to the report" \
  "$REL_OUT" "Scan rows read: 1. Emitted: 1."

# Resolved against the CALLER's directory — the same directory the emitter read
# the file from. A Location anchored anywhere else would name a different file
# than the one whose excerpt the row quotes, trading a silent drop for a silent
# corruption.
(cd "$RELREPO/sub" && bash "$SCAN" --body-only nested.md) >"$TEST_TMPDIR/relsub.txt"
(cd "$RELREPO/sub" && bash "$EMIT" --from "$TEST_TMPDIR/relsub.txt" \
  --out "$TEST_TMPDIR/relsub-find.md" --branch testbranch >/dev/null 2>&1)
RELSUB_OUT=$(cat "$TEST_TMPDIR/relsub-find.md")
assert_contains "a subdirectory-relative row carries its path from the repo root" \
  "$RELSUB_OUT" "| sub/nested.md:3 |"
assert_not_contains "and is not declined" "$RELSUB_OUT" "reason=outside-repo-root"

# A `./` prefix is the same file, and must not reach the Location cell.
(cd "$RELREPO" && bash "$SCAN" --body-only ./doc.md) >"$TEST_TMPDIR/reldot.txt"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/reldot.txt" \
  --out "$TEST_TMPDIR/reldot-find.md" --branch testbranch >/dev/null 2>&1)
assert_contains "a ./-prefixed row normalizes to a bare repo-relative Location" \
  "$(cat "$TEST_TMPDIR/reldot-find.md")" "| doc.md:3 |"

# Admitting relative paths is what makes traversal expressible, so it is refused
# in the same fence. A relative `..` escapes the working tree outright.
(cd "$RELREPO" && bash "$SCAN" --body-only ../outside-doc.md) >"$TEST_TMPDIR/reltrav.txt"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/reltrav.txt" \
  --out "$TEST_TMPDIR/reltrav-find.md" --branch testbranch >/dev/null 2>&1)
TRAV_OUT=$(cat "$TEST_TMPDIR/reltrav-find.md")
TRAV_ROWS=$(printf '%s\n' "$TRAV_OUT" | grep -c '^| [0-9]')
assert_eq "a traversing relative row emits nothing" "0" "$TRAV_ROWS"
assert_contains "and the refusal is counted, never silent" "$TRAV_OUT" "reason=outside-repo-root"

# The anchor test is LEXICAL, so `<root>/../outside.md` prefix-matches the root
# while resolving outside it — it would relativize to `../outside.md` and send
# the fix pass out of the working tree.
printf '%s\n' "$RELREPO/../outside-doc.md:3:I28-a" >"$TEST_TMPDIR/abstrav.txt"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/abstrav.txt" \
  --out "$TEST_TMPDIR/abstrav-find.md" --branch testbranch >/dev/null 2>&1)
ABSTRAV_OUT=$(cat "$TEST_TMPDIR/abstrav-find.md")
ABSTRAV_ROWS=$(printf '%s\n' "$ABSTRAV_OUT" | grep -c '^| [0-9]')
assert_eq "an anchored path holding a .. segment emits nothing" "0" "$ABSTRAV_ROWS"
assert_not_contains "and no traversing Location reaches the report" \
  "$ABSTRAV_OUT" "../outside-doc.md"
assert_contains "the traversal refusal is counted" "$ABSTRAV_OUT" "reason=outside-repo-root"

# Regression guard for the absoluteness test itself: git's own toplevel spelling
# is the drive-letter form under Git Bash, and misreading it as relative would
# decline a row that relativizes correctly today.
RELTOP="$(git -C "$RELREPO" rev-parse --show-toplevel)"
printf '%s\n' "$RELTOP/doc.md:3:I28-a" >"$TEST_TMPDIR/reltop.txt"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/reltop.txt" \
  --out "$TEST_TMPDIR/reltop-find.md" --branch testbranch >/dev/null 2>&1)
RELTOP_OUT=$(cat "$TEST_TMPDIR/reltop-find.md")
assert_contains "a git-toplevel-spelled absolute path still emits" "$RELTOP_OUT" "| doc.md:3 |"
assert_not_contains "and is not re-anchored as a relative path" \
  "$RELTOP_OUT" "reason=outside-repo-root"

# Git Bash / Windows: `\` is a separator (`is_absolute` already treats it as
# one). A slash-only `..` regex misses `..\outside.md`, joins it as
# `<pwd>/..\outside.md`, prefix-matches the root, and emits a traversing
# Location. The file is created under a literal backslash name so source_line
# can read it on POSIX; the fence must still refuse the path form.
printf -- '# Body\n\nCRITICAL: You MUST always do this.\n' >"$RELREPO/..\\outside-doc.md"
printf '%s\n' '..\outside-doc.md:3:I28-a' >"$TEST_TMPDIR/reltravbs.txt"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/reltravbs.txt" \
  --out "$TEST_TMPDIR/reltravbs-find.md" --branch testbranch >/dev/null 2>&1)
TRAVBS_OUT=$(cat "$TEST_TMPDIR/reltravbs-find.md")
TRAVBS_ROWS=$(printf '%s\n' "$TRAVBS_OUT" | grep -c '^| [0-9]')
assert_eq "a backslash-separated relative traversal emits nothing" "0" "$TRAVBS_ROWS"
assert_not_contains "and no backslash-traversing Location reaches the report" \
  "$TRAVBS_OUT" '..\outside-doc.md'
assert_contains "the backslash traversal refusal is counted" \
  "$TRAVBS_OUT" "reason=outside-repo-root"

# Mixed separators: `<root>/..\outside.md` is the same lexical-prefix hole.
printf '%s\n' "$RELREPO/..\\outside-doc.md:3:I28-a" >"$TEST_TMPDIR/mixtrav.txt"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/mixtrav.txt" \
  --out "$TEST_TMPDIR/mixtrav-find.md" --branch testbranch >/dev/null 2>&1)
MIXTRAV_OUT=$(cat "$TEST_TMPDIR/mixtrav-find.md")
MIXTRAV_ROWS=$(printf '%s\n' "$MIXTRAV_OUT" | grep -c '^| [0-9]')
assert_eq "a mixed-separator anchored traversal emits nothing" "0" "$MIXTRAV_ROWS"
assert_contains "and the mixed-separator refusal is counted" \
  "$MIXTRAV_OUT" "reason=outside-repo-root"

# A relative Location that contains `|` must not split the findings table.
# Finding/Action already went through esc(); Location did not, and admitting
# relative paths is what makes a `|` in the filename expressible as written.
printf -- '# Body\n\nCRITICAL: You MUST always do this.\n' >"$RELREPO/p|q.md"
printf '%s\n' 'p|q.md:3:I28-a' >"$TEST_TMPDIR/rellocpipe.txt"
(cd "$RELREPO" && bash "$EMIT" --from "$TEST_TMPDIR/rellocpipe.txt" \
  --out "$TEST_TMPDIR/rellocpipe-find.md" --branch testbranch >/dev/null 2>&1)
LOCPIPE_ROW=$(LC_ALL=C grep -m1 '^| [0-9]' "$TEST_TMPDIR/rellocpipe-find.md")
assert_contains "a pipe in a relative Location is escaped" "$LOCPIPE_ROW" 'p\|q.md:3'
LOCPIPE_COLS=$(printf '%s\n' "$LOCPIPE_ROW" | sed 's/\\|//g' | awk -F'|' '{print NF}')
assert_eq "and the row still parses as one 7-column row" "9" "$LOCPIPE_COLS"

# --- Case 14: I29 description-restatement emits, sibling emits, fences hold --
RESTATE="$TEST_TMPDIR/restate-repo"
mkdir -p "$RESTATE"
git -C "$RESTATE" init -q
# Copy fixtures into the repo so Location is repo-relative.
cp "$FIXTURES/description-restatement.md" "$RESTATE/desc.md"
cp "$FIXTURES/sibling-restatement.md" "$RESTATE/sib.md"
cp "$FIXTURES/quoted-trigger-restatement.md" "$RESTATE/trig.md"
cp "$FIXTURES/partial-overlap.md" "$RESTATE/partial.md"
SCANNER="$SCRIPT_DIR/restatement-scan.py"
python3 "$SCANNER" "$RESTATE/desc.md" "$RESTATE/sib.md" "$RESTATE/trig.md" \
  "$RESTATE/partial.md" >"$TEST_TMPDIR/i29.txt"
(cd "$RESTATE" && bash "$EMIT" --from "$TEST_TMPDIR/i29.txt" \
  --out "$TEST_TMPDIR/i29.md" --branch testbranch >/dev/null 2>&1)
I29_OUT=$(cat "$TEST_TMPDIR/i29.md")
assert_contains "description-restatement reaches the findings file" \
  "$I29_OUT" "rule-description-restatement"
assert_contains "sibling-restatement reaches the findings file" \
  "$I29_OUT" "rule-sibling-restatement"
assert_contains "Action names a body cut, never a description edit" \
  "$I29_OUT" "Do not edit the description"
assert_not_contains "Action never proposes editing when_to_use" \
  "$I29_OUT" "trim the description"
assert_contains "quoted-trigger restatement is declined, not emitted" \
  "$I29_OUT" "reason=quoted-trigger-phrase"
assert_not_contains "partial-overlap is not a finding" \
  "$I29_OUT" "partial.md"

# --- Case 15: the lane-fed path admits I30-I33, fenced and identified --------
# Lane findings arrive in the scanner row shape through --from-lane. Each rule
# keeps the body-scope fence, I31 and I33 stay inside the spoke surfaces their
# remedies are written for, and a frontmatter I32 is a counted decline.
LANEREPO="$TEST_TMPDIR/lane-repo"
LANESKILL="plugins/demo/skills/tool"
mkdir -p "$LANEREPO/$LANESKILL/reference"
git -C "$LANEREPO" init -q
cat >"$LANEREPO/$LANESKILL/SKILL.md" <<'EOF'
---
name: tool
description: Probes hosts; for an unreachable one use /fleet:reachx instead.
---

# Tool

Use `/fleet:reachx` to probe a host that does not answer.

## Stamps

Verified 2026-07-13 against the harness.

The retry now works differently than before.
EOF
cat >"$LANEREPO/$LANESKILL/reference/spoke.md" <<'EOF'
# Spoke

This file is loaded by the hub when the release names a breaking change.

The retry no longer counts toward the budget.
EOF
LANE="$TEST_TMPDIR/lane.txt"
printf '%s\n' \
  "$LANESKILL/SKILL.md:3:I32" \
  "$LANESKILL/SKILL.md:8:I32" \
  "$LANESKILL/SKILL.md:12:I30" \
  "$LANESKILL/SKILL.md:14:I31" \
  "$LANESKILL/SKILL.md:8:I33" \
  "$LANESKILL/reference/spoke.md:3:I33" \
  "$LANESKILL/reference/spoke.md:5:I31" \
  "$LANESKILL/reference/spoke.md:5:I28-a" \
  "$LANESKILL/reference/spoke.md:5:I6" >"$LANE"
lane_emit() { # lane_emit <out> [extra args...] -> stdout of the written file
  local out="$1"
  shift
  (cd "$LANEREPO" && bash "$EMIT" --from-lane "$LANE" --out "$out" --branch testbranch "$@") >/dev/null 2>&1
  cat "$out" 2>/dev/null
}
LOUT="$(lane_emit "$TEST_TMPDIR/lane1.md")"
LROWS="$(printf '%s\n' "$LOUT" | grep '^| [0-9]')"
assert_eq "the lane path alone writes a file with five emitted rows" "5" \
  "$(printf '%s\n' "$LROWS" | grep -c .)"
assert_contains "I30 reaches the findings file from a lane" "$LROWS" \
  "claude-config/audit-instructions/rule-trigger-less-stamp"
assert_contains "I31 in a spoke reaches the findings file" "$LROWS" \
  "| $LANESKILL/reference/spoke.md:5 |"
assert_contains "I32 in the body reaches it, carrying the target it named" "$LROWS" \
  'rule-route-to-absent-skill target="/fleet:reachx"'
assert_contains "I33 on a spoke opener reaches it" "$LROWS" \
  "| $LANESKILL/reference/spoke.md:3 |"
assert_contains "a frontmatter I32 is declined and counted" "$LOUT" \
  "Declined candidates: I32 count=1 reason=frontmatter (body-scope fence)"
assert_not_contains "and never emitted" "$LROWS" "| $LANESKILL/SKILL.md:3 |"
assert_contains "I33 on a SKILL.md is declined and counted" "$LOUT" \
  "count=1 reason=outside-rule-surfaces"
assert_contains "I31 on SKILL.md is emitted" "$LROWS" "| $LANESKILL/SKILL.md:14 |"
assert_not_contains "I33 on SKILL.md is not emitted" "$LROWS" \
  "| $LANESKILL/SKILL.md:8 | claude-config:audit-instructions | claude-config/audit-instructions/rule-spoke-self-description"
assert_contains "a scanner-fed family on the lane path is declined with its path" "$LOUT" \
  "Declined candidates: I28-a count=1 reason=scanner-fed-rule"
assert_contains "a non-crosswalk family on the lane path is declined" "$LOUT" \
  "Declined candidates: I6 count=1 reason=no-severity-crosswalk-row"
assert_contains "the lane rows are counted as read" "$LOUT" "Lane rows read: 9. Emitted from lanes: 5."
assert_contains "the lane rules are named in the Ran line" "$LOUT" "model lanes: I30, I31, I32, I33"
assert_eq "a lane finding omits Confidence" "" \
  "$(printf '%s\n' "$LROWS" | awk -F'|' '{print $4}' | tr -d ' ' | sort -u)"
assert_contains "I32 is CRITICAL and ranks first" "$(printf '%s\n' "$LROWS" | head -n 1)" \
  "| 1 | CRITICAL |  | $LANESKILL/SKILL.md:8 |"
assert_eq "I33 is SUGGESTION and ranks last" "SUGGESTION" \
  "$(printf '%s\n' "$LROWS" | tail -n 1 | awk -F'|' '{print $3}' | tr -d ' ')"
assert_eq "I30 and I31 are IMPORTANT" "IMPORTANT" \
  "$(printf '%s\n' "$LROWS" | grep -E 'rule-(trigger-less-stamp|migration-relative-phrasing)' | awk -F'|' '{print $3}' | tr -d ' ' | sort -u)"

# Remedies, pinned positive and negative in the scope each fires in.
I30_ROW="$(printf '%s\n' "$LROWS" | grep 'rule-trigger-less-stamp')"
assert_contains "I30 Action adds the recheck trigger" "$I30_ROW" "Add the recheck trigger as an observable event"
assert_contains "I30 Action keeps the stamp" "$I30_ROW" "the stamp stays"
assert_not_contains "I30 Action never deletes the stamp" "$I30_ROW" "Delete the stamp"
I31_ROW="$(printf '%s\n' "$LROWS" | grep 'rule-migration-relative-phrasing')"
assert_contains "I31 Action restates the current rule in the present tense" "$I31_ROW" "present tense"
assert_contains "I31 Action names the plugin CHANGELOG as the off-site target for history" "$I31_ROW" \
  "Remediation target for any history worth keeping: plugins/demo/CHANGELOG.md or an ADR"
assert_not_contains "I31 Action never deletes the rule" "$I31_ROW" "Delete the sentence"
I32_ROW="$(printf '%s\n' "$LROWS" | grep 'rule-route-to-absent-skill')"
assert_contains "I32 Action names the skill that exists" "$I32_ROW" "Name the skill that exists"
assert_contains "I32 Action keeps the routing sentence" "$I32_ROW" "Keep the routing sentence"
assert_not_contains "I32 Action never deletes the route" "$I32_ROW" "Delete the route"
I33_ROW="$(printf '%s\n' "$LROWS" | grep 'rule-spoke-self-description')"
assert_contains "I33 Action deletes the self-describing opener" "$I33_ROW" "Delete the opener"
assert_contains "I33 Action keeps the spoke content" "$I33_ROW" "the content below it stays"
assert_contains "I33 Action names the hub as the off-site remediation target" "$I33_ROW" \
  "$LANESKILL/SKILL.md, where that condition is added"

# Identity: every emitted row carries finding_id, stable across runs, and an
# edit to the I33 opener changes that finding's id alone.
assert_eq "every emitted lane row carries a finding_id" "5" \
  "$(printf '%s\n' "$LROWS" | grep -c 'finding_id=[0-9a-f]\{16\} -- ')"
LOUT2="$(lane_emit "$TEST_TMPDIR/lane2.md")"
ids_of() { printf '%s\n' "$1" | grep '^| [0-9]' | grep -o 'finding_id=[0-9a-f]*' | sort; }
assert_eq "two runs over an unchanged tree yield identical finding_id values" \
  "$(ids_of "$LOUT")" "$(ids_of "$LOUT2")"
I33_ID_BEFORE="$(printf '%s\n' "$I33_ROW" | grep -o 'finding_id=[0-9a-f]*')"
I31_ID_BEFORE="$(printf '%s\n' "$I31_ROW" | grep -o 'finding_id=[0-9a-f]*')"
sed -i.bak 's/names a breaking change/ships a breaking change/' "$LANEREPO/$LANESKILL/reference/spoke.md"
LOUT3="$(lane_emit "$TEST_TMPDIR/lane3.md")"
I33_ID_AFTER="$(printf '%s\n' "$LOUT3" | grep 'rule-spoke-self-description' | grep -o 'finding_id=[0-9a-f]*')"
I31_ID_AFTER="$(printf '%s\n' "$LOUT3" | grep 'rule-migration-relative-phrasing' | grep -o 'finding_id=[0-9a-f]*')"
if [[ -n "$I33_ID_AFTER" && "$I33_ID_AFTER" != "$I33_ID_BEFORE" ]]; then
  pass "editing the I33 opener changes that finding's id"
else
  fail "editing the I33 opener changes that finding's id" "before=$I33_ID_BEFORE after=$I33_ID_AFTER"
fi
assert_eq "and leaves the sibling finding's id alone" "$I31_ID_BEFORE" "$I31_ID_AFTER"

# Both paths together: scanner rows rank above lane rows, and a lane rule on
# the scanner path is declined with the path it belongs to.
SCANMIX="$TEST_TMPDIR/scanmix.txt"
cp "$FIXTURES/quoted-trigger.md" "$LANEREPO/qt.md"
printf '%s\n' "qt.md:8:I28-a" "$LANESKILL/reference/spoke.md:5:I31" >"$SCANMIX"
BOTH="$(lane_emit "$TEST_TMPDIR/both.md" --from "$SCANMIX")"
BOTHROWS="$(printf '%s\n' "$BOTH" | grep '^| [0-9]')"
assert_contains "the scanner row ranks above a same-tier lane row, at high confidence" \
  "$(printf '%s\n' "$BOTHROWS" | grep '| IMPORTANT |' | head -n 1)" "| 2 | IMPORTANT | high | qt.md:8 |"
assert_contains "and a CRITICAL lane row still ranks above both" \
  "$(printf '%s\n' "$BOTHROWS" | head -n 1)" "| 1 | CRITICAL |"
assert_contains "a lane rule on the scanner path is declined with its path" "$BOTH" \
  "Declined candidates: I31 count=1 reason=lane-fed-rule"
assert_contains "both intake paths are named in the Ran line" "$BOTH" \
  "(instruction-scan.sh --body-only; model lanes: I30, I31, I32, I33)"

EMPTYLANE="$TEST_TMPDIR/empty-lane.txt"
printf 'no rows here\n' >"$EMPTYLANE"
rc=0
bash "$EMIT" --from-lane "$EMPTYLANE" --out "$TEST_TMPDIR/el.md" --branch x >/dev/null 2>&1 || rc=$?
assert_exit "a lane file with no rows exits 3" 3 "$rc"
rc=0
bash "$EMIT" --from "$LANE" --from-lane "$LANE" --out "$TEST_TMPDIR/same.md" --branch x >/dev/null 2>&1 || rc=$?
assert_exit "one file named as both inputs exits 2" 2 "$rc"
rc=0
bash "$EMIT" --from-lane /nonexistent/lane --out "$TEST_TMPDIR/nl.md" --branch x >/dev/null 2>&1 || rc=$?
assert_exit "a missing --from-lane file exits 2" 2 "$rc"

# --- Case 16: identical sentences in one section collide; I32 target forms ---
DUPREPO="$TEST_TMPDIR/dup-repo"
mkdir -p "$DUPREPO/skills/dup"
git -C "$DUPREPO" init -q
cat >"$DUPREPO/skills/dup/SKILL.md" <<'EOF'
---
name: dup
description: Dup fixture.
---

# Dup

## Stamps

Verified 2026-07-13 against the harness.

Verified 2026-07-13 against the harness.

Sync at 10:30 before routing an unreachable host elsewhere.

Route an unreachable host to `fleet:reachx`.
EOF
DUPLANE="$TEST_TMPDIR/dup-lane.txt"
printf '%s\n' "skills/dup/SKILL.md:10:I30" "skills/dup/SKILL.md:12:I30" \
  "skills/dup/SKILL.md:14:I32" "skills/dup/SKILL.md:16:I32" >"$DUPLANE"
DUPOUT="$( (cd "$DUPREPO" && bash "$EMIT" --from-lane "$DUPLANE" --out "$TEST_TMPDIR/collide.md" --branch x) >/dev/null 2>&1
  cat "$TEST_TMPDIR/collide.md" 2>/dev/null)"
DUPROWS="$(printf '%s\n' "$DUPOUT" | grep '^| [0-9]')"
assert_eq "two identical sentences in one section are reported once" "1" \
  "$(printf '%s\n' "$DUPROWS" | grep -c 'rule-trigger-less-stamp')"
DUP_ID="$(printf '%s\n' "$DUPROWS" | grep 'rule-trigger-less-stamp' | grep -o 'finding_id=[0-9a-f]*')"
assert_contains "the collision is named with its occurrence count" "$DUPOUT" \
  "Identity collisions: $DUP_ID count=2"
assert_contains "the collided row is not counted as emitted twice" "$DUPOUT" "Emitted from lanes: 3."
assert_contains "a clock time is not an I32 target" "$DUPROWS" 'shape="route-to-absent-skill"'
assert_not_contains "no target is read from 10:30" "$DUPROWS" 'target="10:30"'
assert_contains "a backticked bare plugin:skill is an I32 target" "$DUPROWS" 'target="fleet:reachx"'

# --- Case 17: I33 in a references/ spoke; I32 with two candidate targets -----
REFREPO="$TEST_TMPDIR/ref-repo"
mkdir -p "$REFREPO/skills/multi/references"
git -C "$REFREPO" init -q
cat >"$REFREPO/skills/multi/SKILL.md" <<'EOF'
---
name: multi
description: Multi fixture.
---

# Multi

Use /fleet:reach for a live host, or /fleet:reachx for a dead one.
EOF
cat >"$REFREPO/skills/multi/references/spoke.md" <<'EOF'
# Spoke

This file is loaded by the hub when the release names a breaking change.
EOF
REFLANE="$TEST_TMPDIR/ref-lane.txt"
printf '%s\n' "skills/multi/SKILL.md:8:I32" "skills/multi/references/spoke.md:3:I33" >"$REFLANE"
REFOUT="$( (cd "$REFREPO" && bash "$EMIT" --from-lane "$REFLANE" --out "$TEST_TMPDIR/refs.md" --branch x) >/dev/null 2>&1
  cat "$TEST_TMPDIR/refs.md" 2>/dev/null)"
assert_contains "I33 on a references/ spoke opener is emitted" "$REFOUT" \
  "| skills/multi/references/spoke.md:3 |"
assert_contains "an I32 line with two candidate targets names no target" \
  "$(printf '%s\n' "$REFOUT" | grep 'skills/multi/SKILL.md:8')" 'shape="route-to-absent-skill"'

# --- Case 18: I31/I33 surfaces follow criteria.md; the I32 tier follows the arm -
# I31 covers SKILL.md and every file a skill loads (actions/, root-level and
# <slice>/README.md spokes); I33 covers the same minus SKILL.md, and names the
# nearest SKILL.md above the spoke as its hub. A file outside any skill
# directory is declined and counted. I32 is CRITICAL under plugins/ and
# IMPORTANT on a user or project surface.
SURFREPO="$TEST_TMPDIR/surf-repo"
SURFSKILL="plugins/demo/skills/tool"
mkdir -p "$SURFREPO/$SURFSKILL/actions" "$SURFREPO/$SURFSKILL/slice" "$SURFREPO/docs" "$SURFREPO/.claude/rules"
git -C "$SURFREPO" init -q
cat >"$SURFREPO/$SURFSKILL/SKILL.md" <<'EOF'
---
name: tool
description: Surface fixture.
---

# Tool

The retry no longer counts toward the budget.

Use `/fleet:reachx` to probe a host that does not answer.
EOF
printf '%s\n' '# Act' '' 'The retry no longer counts toward the budget.' >"$SURFREPO/$SURFSKILL/actions/act.md"
printf '%s\n' '# Formats' '' 'This file is loaded by the hub when the skill writes output.' >"$SURFREPO/$SURFSKILL/formats.md"
printf '%s\n' '# Slice' '' 'This file is loaded by the hub for the slice.' >"$SURFREPO/$SURFSKILL/slice/README.md"
printf '%s\n' '# Notes' '' 'The retry no longer counts toward the budget.' >"$SURFREPO/docs/notes.md"
# shellcheck disable=SC2016 # the backticks are fixture text, not a command substitution
printf '%s\n' '# Rule' '' 'Use `/fleet:reachx` to probe a host that does not answer.' >"$SURFREPO/.claude/rules/route.md"
SURFLANE="$TEST_TMPDIR/surf-lane.txt"
printf '%s\n' \
  "$SURFSKILL/SKILL.md:8:I31" \
  "$SURFSKILL/actions/act.md:3:I31" \
  "$SURFSKILL/formats.md:3:I33" \
  "$SURFSKILL/slice/README.md:3:I33" \
  "docs/notes.md:3:I31" \
  "$SURFSKILL/SKILL.md:10:I32" \
  ".claude/rules/route.md:3:I32" >"$SURFLANE"
SURFOUT="$( (cd "$SURFREPO" && bash "$EMIT" --from-lane "$SURFLANE" --out "$TEST_TMPDIR/surf.md" --branch x) >/dev/null 2>&1
  cat "$TEST_TMPDIR/surf.md" 2>/dev/null)"
SURFROWS="$(printf '%s\n' "$SURFOUT" | grep '^| [0-9]')"
assert_contains "I31 in a SKILL.md is emitted" "$SURFROWS" "| $SURFSKILL/SKILL.md:8 |"
assert_contains "I31 in an actions/ file is emitted" "$SURFROWS" "| $SURFSKILL/actions/act.md:3 |"
assert_contains "I33 in a root-level spoke is emitted" "$SURFROWS" "| $SURFSKILL/formats.md:3 |"
assert_contains "I33 in a <slice>/README.md spoke is emitted" "$SURFROWS" "| $SURFSKILL/slice/README.md:3 |"
assert_contains "the I33 hub of a root-level spoke is the SKILL.md beside it" \
  "$(printf '%s\n' "$SURFROWS" | grep 'formats.md:3')" "loading condition: $SURFSKILL/SKILL.md, where"
assert_contains "the I33 hub of a slice README is the nearest SKILL.md above it" \
  "$(printf '%s\n' "$SURFROWS" | grep 'slice/README.md:3')" "loading condition: $SURFSKILL/SKILL.md, where"
SUBLANE="$TEST_TMPDIR/sub-lane.txt"
printf '%s\n' "formats.md:3:I33" >"$SUBLANE"
(cd "$SURFREPO/$SURFSKILL" && bash "$EMIT" --from-lane "$SUBLANE" --out "$TEST_TMPDIR/sub.md" --branch x) >/dev/null 2>&1
assert_contains "the I33 hub is found when run from a subdirectory with a relative path" \
  "$(grep 'formats.md:3' "$TEST_TMPDIR/sub.md" 2>/dev/null)" "loading condition: $SURFSKILL/SKILL.md, where"
assert_contains "I31 in a file outside any skill dir is declined and counted" "$SURFOUT" \
  "Declined candidates: I31 count=1 reason=outside-rule-surfaces"
assert_not_contains "and never emitted" "$SURFROWS" "| docs/notes.md:3 |"
assert_eq "an I32 under plugins/ is CRITICAL" "CRITICAL" \
  "$(printf '%s\n' "$SURFROWS" | grep "SKILL.md:10 " | awk -F'|' '{print $3}' | tr -d ' ')"
assert_eq "an I32 on a project surface is IMPORTANT" "IMPORTANT" \
  "$(printf '%s\n' "$SURFROWS" | grep '.claude/rules/route.md:3 ' | awk -F'|' '{print $3}' | tr -d ' ')"
assert_contains "the CRITICAL I32 ranks above the IMPORTANT one" \
  "$(printf '%s\n' "$SURFROWS" | head -n 1)" "| CRITICAL |"

# --- Summary -----------------------------------------------------------------
printf '\n'
if [[ "$FAILED" -gt 0 ]]; then
  printf '%d of %d checks FAILED.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf 'All %d checks passed.\n' "$CASE_NUM"
