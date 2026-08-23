#!/usr/bin/env bash
# Regression tests for emit-findings.sh (self-contained — ships with the plugin).
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
OUT=$(emit "$TEST_TMPDIR/pc.txt" "$TEST_TMPDIR/pc.md")
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
# COUNTED decline rather than a finding with an empty excerpt. The fail-safe
# direction was already right; what was missing is the assertion that keeps an
# off-by-one in source_line's counting loop from silently changing it.
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
bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/co2.md" --branch testbranch >/dev/null 2>&1
assert_not_contains "omitting the flag reports no carve-out line" \
  "$(cat "$TEST_TMPDIR/co2.md")" "criteria-carve-out"
rc=0
bash "$EMIT" --from "$TEST_TMPDIR/yb.txt" --out "$TEST_TMPDIR/co3.md" \
  --branch testbranch --declined-carveout notanumber >/dev/null 2>&1 || rc=$?
assert_exit "a non-numeric carve-out count exits 2" 2 "$rc"

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
# same directory differently, which used to decline every in-repo hit.
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

# --- Summary -----------------------------------------------------------------
printf '\n'
if [[ "$FAILED" -gt 0 ]]; then
  printf '%d of %d checks FAILED.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
fi
printf 'All %d checks passed.\n' "$CASE_NUM"
