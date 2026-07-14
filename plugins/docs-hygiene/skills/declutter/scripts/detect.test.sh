#!/usr/bin/env bash
# Self-contained tests for detect.sh (no external test lib — ships with the
# plugin; fixtures are built inline in a tmpdir).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
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

# --- Fixtures (built inline; no shipped fixture files) ---------------------------

ALL_SHAPES="$TEST_TMPDIR/all-shapes.md"
cat >"$ALL_SHAPES" <<'EOF'
# Fixture: every shape

The plan lives at .work/foo-slice/PLAN.md for this effort.

## Why this file exists

Empirically observed 2026-01-01 during the rollout.

The following five skills consume this rule.

- `/skill-a` — does one thing
- `/skill-b` — does another

Path-scoped to `src/**` so it loads there.
EOF

CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
# Clean fixture

Plain prose with no noise shapes. The schema uses .work/<slug>/PLAN.md as a
slot-variable example, which is not a ghost ref. Contract slices land in
docs/topics/<slug>/PLAN.md; session handoffs sit in .work/handoffs/ and review
reports in .work/reviews/<branch-slug>/; .claude/topic-docs.yaml is the tracked
concern file.

## Cross-references

Was renamed to something — exempt section, never flagged.
EOF

OPTOUT="$TEST_TMPDIR/legit-optouts.md"
cat >"$OPTOUT" <<'EOF'
# Opt-out fixture

<!-- markdown-discipline-ignore -->
Empirically observed during the bar-rollout window.

<!-- markdown-discipline-ignore-line -->
We pivoted from the 2026-05-01 incident layout.

Path-scoped to `docs/**` per the loader.
EOF

# --- 1. --help contract -----------------------------------------------------------

help_exit=0
bash "$DETECT" --help >/dev/null 2>&1 || help_exit=$?
assert_exit "--help exits 0" 0 "$help_exit"

unknown_exit=0
bash "$DETECT" --bogus >/dev/null 2>&1 || unknown_exit=$?
assert_exit "unknown flag exits 2" 2 "$unknown_exit"

# --- 2. All shapes detected --------------------------------------------------------

out="$(bash "$DETECT" "$ALL_SHAPES")"
assert_contains "ghost-ref finding" "$out" "Finding shape: ghost-ref"
assert_contains "citation finding" "$out" "Finding shape: citation"
assert_contains "enum-list finding" "$out" "Finding shape: enum-list"
assert_contains "scope-meta finding" "$out" "Finding shape: scope-meta"
assert_contains "preamble finding" "$out" "Finding shape: preamble"
assert_contains "preamble tier 2" "$out" "Finding tier: 2"
assert_contains "file summary" "$out" "Summary file: $ALL_SHAPES"

# --- 3. Clean fixture: slot-variable not flagged; exempt section skipped -----------

clean_out="$(bash "$DETECT" "$CLEAN")"
assert_contains "clean summary present" "$clean_out" "Summary total:"
assert_not_contains "slot-variable not a ghost ref" "$clean_out" "Finding shape: ghost-ref"
assert_not_contains "exempt section suppressed" "$clean_out" "Finding shape: citation"

# --- 4. Opt-out markers suppress wrapped content ------------------------------------

opt_out="$(bash "$DETECT" "$OPTOUT")"
assert_not_contains "opt-out citation suppressed" "$opt_out" "bar-rollout"
assert_not_contains "opt-out line suppressed" "$opt_out" "2026-05-01 incident"
assert_contains "scope-meta still detected" "$opt_out" "Finding shape: scope-meta"

# --- 5. Backtick-wrapped slash-command roster detected ------------------------------

BT_FIXTURE="$TEST_TMPDIR/bt.md"
cat >"$BT_FIXTURE" <<'EOF'
- `/skill-z` — backtick-wrapped slash command
EOF
bt_out="$(bash "$DETECT" "$BT_FIXTURE")"
assert_contains "backtick enum-list detected" "$bt_out" "Finding shape: enum-list"

# --- 6. Directory target expands to its .md files ------------------------------------

DIR_FIXTURE="$TEST_TMPDIR/dir-target/nested"
mkdir -p "$DIR_FIXTURE"
cp "$ALL_SHAPES" "$DIR_FIXTURE/inner.md"
dir_out="$(bash "$DETECT" "$TEST_TMPDIR/dir-target")"
assert_contains "directory target audits nested .md" "$dir_out" "Summary file: $DIR_FIXTURE/inner.md"
assert_contains "directory target finds shapes" "$dir_out" "Finding shape: ghost-ref"

# --- 7. --paths-file input ----------------------------------------------------------

PATHS="$TEST_TMPDIR/paths.txt"
printf '%s\n' "$CLEAN" >"$PATHS"
pf_out="$(bash "$DETECT" --paths-file "$PATHS")"
assert_contains "paths-file target audited" "$pf_out" "Summary file: $CLEAN"

# --- 8. Topic-docs taxonomy: concrete contract slice flags; convention forms pass ----

TAXONOMY="$TEST_TMPDIR/taxonomy.md"
cat >"$TAXONOMY" <<'EOF'
# Taxonomy fixture

The worked example lives at docs/topics/net-hardening/PLAN.md on the branch.
EOF
tax_out="$(bash "$DETECT" "$TAXONOMY")"
assert_contains "concrete contract-slice path is a ghost ref" "$tax_out" "Finding shape: ghost-ref"

# --- 9. Retired .claude/notes/ location always flags ----------------------------------

NOTES="$TEST_TMPDIR/notes.md"
cat >"$NOTES" <<'EOF'
# Notes fixture

Older drafts sit under .claude/notes/net-hardening/ for this rule.
EOF
notes_out="$(bash "$DETECT" "$NOTES")"
assert_contains "retired .claude/notes/ citation flags" "$notes_out" "Finding shape: ghost-ref"

MIGRATE="$TEST_TMPDIR/migrate.md"
cat >"$MIGRATE" <<'EOF'
# Migration fixture

Move .claude/notes/<slug>/ content into .work/<slug>/ before the sunset.
EOF
mig_out="$(bash "$DETECT" "$MIGRATE")"
assert_contains ".claude/notes/ flags even beside convention placeholders" "$mig_out" "Finding shape: ghost-ref"

# --- 10. Per-match exemption: convention tokens never mask concrete ghost refs --------

MIXED="$TEST_TMPDIR/mixed-line.md"
cat >"$MIXED" <<'EOF'
# Mixed-line fixture

See docs/topics/auth-fix/PLAN.md and the concern file .claude/topic-docs.yaml for detail.
EOF
mixed_out="$(bash "$DETECT" "$MIXED")"
assert_contains "concern-file token does not exempt a concrete slice on the same line" "$mixed_out" "Finding shape: ghost-ref"

DEEP="$TEST_TMPDIR/deep-review.md"
cat >"$DEEP" <<'EOF'
# Deep-review fixture

Review report kept at .work/reviews/pr-123-auth/20260101T000000Z-self.md for posterity.
EOF
deep_out="$(bash "$DETECT" "$DEEP")"
assert_contains "concrete child under .work/reviews/ is a ghost ref" "$deep_out" "Finding shape: ghost-ref"

DIGIT="$TEST_TMPDIR/digit-slug.md"
cat >"$DIGIT" <<'EOF'
# Digit-slug fixture

Plan lives at docs/topics/2026-migration/PLAN.md today.
EOF
digit_out="$(bash "$DETECT" "$DIGIT")"
assert_contains "digit-leading slug is a ghost ref" "$digit_out" "Finding shape: ghost-ref"

BARE_ROOT="$TEST_TMPDIR/bare-root.md"
cat >"$BARE_ROOT" <<'EOF'
# Bare-root fixture

.work/reviews/ is self-ignoring
EOF
bare_out="$(bash "$DETECT" "$BARE_ROOT")"
assert_not_contains "bare concern root is not a ghost ref" "$bare_out" "Finding shape: ghost-ref"

PLACEHOLDER="$TEST_TMPDIR/placeholder.md"
cat >"$PLACEHOLDER" <<'EOF'
# Placeholder fixture

docs/topics/<slug>/PLAN.md
EOF
ph_out="$(bash "$DETECT" "$PLACEHOLDER")"
assert_not_contains "slot-variable placeholder is not a ghost ref" "$ph_out" "Finding shape: ghost-ref"

# --- Final report --------------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
