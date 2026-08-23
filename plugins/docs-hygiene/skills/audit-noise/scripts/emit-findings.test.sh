#!/usr/bin/env bash
# Self-contained tests for emit-findings.sh (no external test lib — ships with
# the plugin; fixtures are built inline in a tmpdir).
set -uo pipefail

# A fixture must never inherit ambient git environment: an absolute GIT_DIR
# overrides repository DISCOVERY outright, and GIT_CONFIG replaces the file
# `git config` reads and writes, so either one lands a throwaway fixture's
# identity in the CALLER's repository. `git -C` does not protect against
# either.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
EMIT="$SCRIPT_DIR/emit-findings.sh"
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
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

# --- Fixtures -----------------------------------------------------------------------

NEG="$TEST_TMPDIR/neg.md"
cat >"$NEG" <<'EOF'
# Bare prohibitions

Do not use markdown in your response.

Never force-push to a shared branch.
EOF

MIXED="$TEST_TMPDIR/mixed.md"
cat >"$MIXED" <<'EOF'
# Mixed shapes

Empirically observed 2026-01-01 during the rollout.

The plan lives at .work/foo-slice/PLAN.md for this effort.

Avoid deep nesting.
EOF

CLEAN="$TEST_TMPDIR/clean.md"
printf '# Clean\n\nOrdinary prose with nothing to report.\n' >"$CLEAN"

bash "$DETECT" "$NEG" >"$TEST_TMPDIR/neg-out.txt" 2>&1
bash "$DETECT" "$MIXED" >"$TEST_TMPDIR/mixed-out.txt" 2>&1
bash "$DETECT" "$CLEAN" >"$TEST_TMPDIR/clean-out.txt" 2>&1

# --- 1. Usage contract ---------------------------------------------------------------

rc=0
bash "$EMIT" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

rc=0
bash "$EMIT" --bogus >/dev/null 2>&1 || rc=$?
assert_exit "unknown argument exits 2" 2 "$rc"

rc=0
bash "$EMIT" --from "$TEST_TMPDIR/neg-out.txt" >/dev/null 2>&1 || rc=$?
assert_exit "missing --out exits 2" 2 "$rc"

rc=0
bash "$EMIT" --from "$TEST_TMPDIR/nope.txt" --out "$TEST_TMPDIR/x.md" >/dev/null 2>&1 || rc=$?
assert_exit "missing --from file exits 2" 2 "$rc"

# --- 2. Not detector output is refused, not composed from ----------------------------

rc=0
bash "$EMIT" --from "$EMIT" --out "$TEST_TMPDIR/garbage.md" --branch t >/dev/null 2>&1 || rc=$?
assert_exit "non-detector input exits 3" 3 "$rc"
if [[ -e "$TEST_TMPDIR/garbage.md" ]]; then
  fail "non-detector input writes no file" "no file" "garbage.md was created"
else
  pass "non-detector input writes no file"
fi

# --- 3. branch: proves ownership, so an unresolvable branch REFUSES ------------------
#
# fix-pass-mode.md "Step 1" admits a candidate only when its branch: equals the
# current branch EXACTLY. With no branch there is nothing correct to write, and
# a file the relay can never match is worse than no file. GIT_DIR is pointed at
# a nonexistent path as the hermetic stand-in for CI's detached-HEAD checkout.
# fixture-isolation-note: this export is scoped to one command, and the suite
# clears the inherited environment at its top.
rc=0
GIT_DIR="$TEST_TMPDIR/no-such-git-dir" bash "$EMIT" \
  --from "$TEST_TMPDIR/neg-out.txt" --out "$TEST_TMPDIR/nb.md" >/dev/null 2>&1 || rc=$?
assert_exit "no --branch and no current branch exits 2" 2 "$rc"
if [[ -e "$TEST_TMPDIR/nb.md" ]]; then
  fail "an unresolvable branch writes no file" "no file" "nb.md was created"
else
  pass "an unresolvable branch writes no file"
fi

rc=0
GIT_DIR="$TEST_TMPDIR/no-such-git-dir" bash "$EMIT" \
  --from "$TEST_TMPDIR/neg-out.txt" --out "$TEST_TMPDIR/nb2.md" --branch explicit >/dev/null 2>&1 || rc=$?
assert_exit "an explicit --branch works with no git branch" 0 "$rc"
assert_contains "the explicit branch is what gets written" "$(cat "$TEST_TMPDIR/nb2.md")" "branch: explicit"

# --- 4. Frontmatter is the admission test -------------------------------------------

bash "$EMIT" --from "$TEST_TMPDIR/neg-out.txt" --out "$TEST_TMPDIR/f/neg.md" --branch test-branch >/dev/null 2>&1
FOUT="$(cat "$TEST_TMPDIR/f/neg.md")"
assert_contains "type: review-findings" "$FOUT" "type: review-findings"
assert_contains "branch: is the passed branch" "$FOUT" "branch: test-branch"
assert_contains "a parseable Findings table" "$FOUT" "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"
assert_not_contains "tier: is omitted (no analogue)" "$FOUT" "tier: "

# `date:` is PARSED by the consumer: fix-pass-mode.md "Step 1" reads it only as a
# full ISO-8601 date-time with an explicit UTC designator, so the time portion
# needs COLONS. The colon-free rule binds the FILE NAME, never this field.
if LC_ALL=C grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$TEST_TMPDIR/f/neg.md"; then
  pass "date: is ISO-8601 extended with colons and a Z designator"
else
  fail "date: is ISO-8601 extended with colons and a Z designator" "date: YYYY-MM-DDTHH:MM:SSZ" \
    "$(LC_ALL=C grep '^date:' "$TEST_TMPDIR/f/neg.md")"
fi

# --- 5. Producer-owned cells ---------------------------------------------------------

assert_contains "Finding leads with the qualified rule id" "$FOUT" \
  "docs-hygiene/audit-noise/rule-negation-without-positive"
assert_contains "Finding carries the fired condition in the run's own values" "$FOUT" \
  'cue="Do not", positive-clauses=0'
assert_contains "the other cue is reported as itself" "$FOUT" 'cue="Never", positive-clauses=0'
assert_contains "Tier is the crosswalk's SUGGESTION" "$FOUT" "| SUGGESTION | high |"
assert_not_contains "Confidence is never low" "$FOUT" "| low |"
assert_contains "Surface(s) names this producer" "$FOUT" "docs-hygiene:audit-noise"

# --- 6. Roster agreement: only tabled rules reach the relay ---------------------------
#
# The emitter declares itself a MIRROR of the severity crosswalk, and a mirror
# nothing compares drifts silently. detect.sh ships SIX shapes and exactly one
# has a crosswalk row, so the other five must be counted as declined rather than
# emitted. Both halves are checked: the emitted set, and the roster itself — a
# seventh shape fails here until it is tabled or explicitly declined.

EXPECTED_ROSTER="citation
enum-list
ghost-ref
negation-without-positive
preamble
scope-meta"
ALL_SHAPES_FIX="$TEST_TMPDIR/all-shapes.md"
cat >"$ALL_SHAPES_FIX" <<'EOF'
# every shape

The plan lives at .work/foo-slice/PLAN.md for this effort.

## Why this file exists

Empirically observed 2026-01-01 during the rollout.

The following five skills consume this rule.

Path-scoped to `src/**` so it loads there.

Do not use markdown in your response.
EOF
ROSTER="$(bash "$DETECT" "$ALL_SHAPES_FIX" | LC_ALL=C sed -n 's/^Finding shape: //p' | sort -u)"
if [[ "$ROSTER" == "$EXPECTED_ROSTER" ]]; then
  pass "roster agreement: detect.sh ships exactly the six tabled shapes"
else
  fail "roster agreement: detect.sh ships exactly the six tabled shapes" "$EXPECTED_ROSTER" "$ROSTER"
fi

bash "$EMIT" --from "$TEST_TMPDIR/mixed-out.txt" --out "$TEST_TMPDIR/f/mixed.md" --branch test-branch >/dev/null 2>&1
MOUT="$(cat "$TEST_TMPDIR/f/mixed.md")"
assert_contains "the tabled rule is emitted as a row" "$MOUT" "rule-negation-without-positive"
assert_not_contains "an untabled shape emits no row" "$MOUT" "| SUGGESTION | high | $MIXED:4"
assert_contains "an untabled shape is COUNTED, not dropped" "$MOUT" \
  "Declined candidates: docs-hygiene/audit-noise/rule-citation count=1 reason=no-severity-crosswalk-row"
assert_contains "every untabled shape gets its own count" "$MOUT" \
  "Declined candidates: docs-hygiene/audit-noise/rule-ghost-ref count=1 reason=no-severity-crosswalk-row"

# The emitting rule's own declines are NOT tallied, and the artifact says so
# rather than carrying a number nothing computed — a candidate declined at
# selection never becomes a detector record for the emitter to see. Asserting
# the literal keeps a future "count=0" from silently asserting full coverage.
assert_contains "the emitting rule's own declines are declared not-tallied" "$MOUT" \
  "Declined candidates: docs-hygiene/audit-noise/rule-negation-without-positive count=not-tallied-v1 reason=declined-at-selection-before-any-record"
assert_not_contains "no fabricated zero-count for the emitting rule" "$MOUT" \
  "rule-negation-without-positive count=0"

# --- 7. Coverage is the payload -------------------------------------------------------

bash "$EMIT" --from "$TEST_TMPDIR/clean-out.txt" --out "$TEST_TMPDIR/f/clean.md" --branch test-branch >/dev/null 2>&1
if [[ -f "$TEST_TMPDIR/f/clean.md" ]] && LC_ALL=C grep -q '^## Findings' "$TEST_TMPDIR/f/clean.md"; then
  pass "zero findings still writes (coverage is the payload)"
else
  fail "zero findings still writes (coverage is the payload)" "file with empty Findings header" "missing"
fi
assert_contains "a rule that returned nothing says so" "$(cat "$TEST_TMPDIR/f/clean.md")" \
  "Returned no result: [docs-hygiene/audit-noise/rule-negation-without-positive]."

# --- 8. Cell escaping ------------------------------------------------------------------
#
# This detector reads DOCUMENTS, so excerpts carry markdown table pipes as a
# matter of course. An unescaped pipe shifts every later cell, which parses
# WRONG rather than failing — the loudest way a first detector ships a broken
# file.

PIPED="$TEST_TMPDIR/piped-out.txt"
cat >"$PIPED" <<'EOF'
File: doc.md
Finding tier: 2
Finding shape: negation-without-positive
Finding line: 7
Finding excerpt: Do not pipe a | into a cell.
---
Summary total: files=1 T1=0 T2=1 T3=0
EOF
bash "$EMIT" --from "$PIPED" --out "$TEST_TMPDIR/f/piped.md" --branch test-branch >/dev/null 2>&1
assert_contains "a pipe in the excerpt is escaped" "$(cat "$TEST_TMPDIR/f/piped.md")" 'a \| into a cell'

# --- 9. Non-overwrite naming ------------------------------------------------------------

bash "$EMIT" --from "$TEST_TMPDIR/neg-out.txt" --out "$TEST_TMPDIR/f/neg.md" --branch test-branch >"$TEST_TMPDIR/second.txt" 2>&1
assert_contains "an existing path takes the -2 suffix" "$(cat "$TEST_TMPDIR/second.txt")" "neg-2.md"
if [[ -f "$TEST_TMPDIR/f/neg-2.md" ]]; then
  pass "the suffixed file is the one written"
else
  fail "the suffixed file is the one written" "neg-2.md exists" "missing"
fi

# --- 10. Location is repo-relative -------------------------------------------------------
#
# The fix action fences each remediation to its finding's Location, so an
# absolute path is not portable to the checkout that applies the fix.

FIXREPO="$TEST_TMPDIR/repo"
mkdir -p "$FIXREPO"
(
  cd "$FIXREPO" || exit 1
  git init -q .
  git config user.email fixture@example.invalid
  git config user.name Fixture
) >/dev/null 2>&1
mkdir -p "$FIXREPO/docs"
printf '# d\n\nDo not use markdown in your response.\n' >"$FIXREPO/docs/d.md"
(
  cd "$FIXREPO" || exit 1
  bash "$DETECT" docs/d.md >"$TEST_TMPDIR/rel-out.txt" 2>&1
  bash "$EMIT" --from "$TEST_TMPDIR/rel-out.txt" --out "$TEST_TMPDIR/f/rel.md" --branch test-branch >/dev/null 2>&1
)
assert_contains "Location is repo-relative" "$(cat "$TEST_TMPDIR/f/rel.md")" "| docs/d.md:3 |"
assert_not_contains "Location carries no absolute prefix" "$(cat "$TEST_TMPDIR/f/rel.md")" "$FIXREPO/docs"

# --- Final report ------------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
