#!/usr/bin/env bash
# Self-contained tests for emit-findings.sh, driven against the committed fixture
# tree in fixtures/tree via fixtures/build-fixture.sh.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/emit-findings.sh"
INVENTORY="$SCRIPT_DIR/inventory.sh"
SWEEP="$SCRIPT_DIR/sweep.sh"
BUILD="$SCRIPT_DIR/fixtures/build-fixture.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

new_fixture() {
  d="$TEST_TMPDIR/fx-$CASES-$RANDOM"
  bash "$BUILD" "$d" ${1:+--variant "$1"} >/dev/null
  printf '%s' "$d"
}

# audit <root> <workdir> : run the three stages, leave inv/sweep/plan behind
audit() {
  mkdir -p "$2"
  bash "$INVENTORY" --root "$1" >"$2/inv.tsv"
  awk -F'\t' '$1=="OFFENDER" {print $2 "\t" $3}' "$2/inv.tsv" >"$2/pairs.tsv"
  bash "$SWEEP" --root "$1" --pairs "$2/pairs.tsv" >"$2/sweep.tsv"
  bash "$SUT" --root "$1" --inventory "$2/inv.tsv" --sweep "$2/sweep.tsv" --out "$2/plan.md"
}

# --- a plan from the clean fixture -------------------------------------------

root="$(new_fixture)"
work="$TEST_TMPDIR/w1"
out="$(audit "$root" "$work")"
plan="$(cat "$work/plan.md")"

assert_contains "the run reports what it wrote" "$out" "3 finding(s)"
assert_contains "the artifact declares its own type" "$plan" "type: docs-hygiene-file-name-findings"
assert_contains "the artifact is never the auto-apply findings type" "$plan" "schema: 1"
assert_eq "the type is not review-findings" "0" "$(printf '%s\n' "$plan" | grep -c 'type: review-findings' || true)"
assert_eq "one record per offender" "3" "$(printf '%s\n' "$plan" | grep -c '^### FN-')"
assert_contains "the branch is recorded" "$plan" "branch: "
assert_contains "the head is recorded for the evidence trail" "$plan" "head: "
assert_contains "the scanned count is carried over" "$plan" "files_scanned: 8"
assert_contains "a collision count is stated even when zero" "$plan" "collisions: 0"

assert_contains "each record opens pending" "$plan" "- **Status:** pending"
assert_contains "each record names its site total" "$plan" "- **References:**"
assert_contains "each record breaks the sites down by tier" "$plan" "- **By tier:**"
assert_contains "each record counts the sites needing a human" "$plan" "- **Needs a human:**"
assert_contains "a generated file touched by a rename is named" "$plan" "build/out.json"
assert_contains "every site is listed with its form, tier, and action" "$plan" "| file | line | form | tier | action | excerpt |"

# --- ids come from the old path, not from rank -------------------------------

id_a="$(grep -m1 '^### FN-.*Alpha-One' "$work/plan.md" | awk '{print $2}')"
assert_eq "an id is eight hex characters behind FN-" "1" "$(printf '%s' "$id_a" | grep -cE '^FN-[0-9a-f]{8}$')"

work2="$TEST_TMPDIR/w2"
audit "$root" "$work2" >/dev/null
id_a2="$(grep -m1 '^### FN-.*Alpha-One' "$work2/plan.md" | awk '{print $2}')"
assert_eq "the same file keeps the same id across runs" "$id_a" "$id_a2"

# --- a re-audit merges rather than overwriting decisions ----------------------

sed -i.bak "/^### $id_a /,/^- \*\*Collision/ s/^- \*\*Status:\*\* pending/- **Status:** declined/" "$work/plan.md"
rm -f "$work/plan.md.bak"
audit "$root" "$work" >/dev/null
assert_eq "a declined decision survives a re-audit" "1" "$(grep -c '^- \*\*Status:\*\* declined' "$work/plan.md")"
assert_eq "the other records are still pending" "2" "$(grep -c '^- \*\*Status:\*\* pending' "$work/plan.md")"

# --- --replace starts fresh ---------------------------------------------------

bash "$SUT" --root "$root" --inventory "$work/inv.tsv" --sweep "$work/sweep.tsv" \
  --out "$work/plan.md" --replace >/dev/null
assert_eq "--replace drops the carried decisions" "0" "$(grep -c '^- \*\*Status:\*\* declined' "$work/plan.md" || true)"

# --- a branch mismatch refuses ------------------------------------------------

sed -i.bak 's/^branch: .*/branch: some-other-branch/' "$work/plan.md"
rm -f "$work/plan.md.bak"
assert_eq "an artifact from another branch is refused" "2" "$(
  bash "$SUT" --root "$root" --inventory "$work/inv.tsv" --sweep "$work/sweep.tsv" --out "$work/plan.md" >/dev/null 2>&1
  printf '%s' "$?"
)"

# --- a collision refuses the whole plan ---------------------------------------

root="$(new_fixture collision)"
work="$TEST_TMPDIR/w3"
mkdir -p "$work"
bash "$INVENTORY" --root "$root" >"$work/inv.tsv"
awk -F'\t' '$1=="OFFENDER" {print $2 "\t" $3}' "$work/inv.tsv" >"$work/pairs.tsv"
bash "$SWEEP" --root "$root" --pairs "$work/pairs.tsv" >"$work/sweep.tsv"
err="$(bash "$SUT" --root "$root" --inventory "$work/inv.tsv" --sweep "$work/sweep.tsv" --out "$work/plan.md" 2>&1 >/dev/null)"
assert_eq "a collision exits 1" "1" "$(
  bash "$SUT" --root "$root" --inventory "$work/inv.tsv" --sweep "$work/sweep.tsv" --out "$work/plan.md" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_contains "the colliding pair is named on stderr" "$err" "docs/beta.md"
assert_contains "the reason is stated, not just the refusal" "$err" "case-insensitive checkout"
assert_eq "nothing is written when a collision stands" "0" "$([[ -e "$work/plan.md" ]] && printf 1 || printf 0)"

# --- garbage input refuses rather than composing ------------------------------

printf 'this is not inventory output\n' >"$TEST_TMPDIR/garbage.tsv"
assert_eq "an input with no records exits 3" "3" "$(
  bash "$SUT" --root "$root" --inventory "$TEST_TMPDIR/garbage.tsv" --sweep "$TEST_TMPDIR/garbage.tsv" --out "$TEST_TMPDIR/never.md" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "and writes nothing" "0" "$([[ -e "$TEST_TMPDIR/never.md" ]] && printf 1 || printf 0)"

# --- read-only on the tree ----------------------------------------------------

root="$(new_fixture)"
work="$TEST_TMPDIR/w4"
audit "$root" "$work" >/dev/null
assert_eq "the audited tree is byte-identical afterwards" "" "$(git -C "$root" status --porcelain)"

# --- a detached checkout still names its own branch slug ----------------------

git -C "$root" checkout -q --detach >/dev/null 2>&1
bash "$SUT" --root "$root" --inventory "$work/inv.tsv" --sweep "$work/sweep.tsv" \
  --out "$work/detached-plan.md" >/dev/null
assert_contains "a detached head slugs by its short sha" "$(cat "$work/detached-plan.md")" "branch: detached-"
assert_eq "and a branch change is refused rather than silently rewritten" "2" "$(
  bash "$SUT" --root "$root" --inventory "$work/inv.tsv" --sweep "$work/sweep.tsv" --out "$work/plan.md" >/dev/null 2>&1
  printf '%s' "$?"
)"

# --- usage --------------------------------------------------------------------

assert_eq "--help exits 0" "0" "$(
  bash "$SUT" --help >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "a missing --out exits 2" "2" "$(
  bash "$SUT" --inventory "$work/inv.tsv" --sweep "$work/sweep.tsv" >/dev/null 2>&1
  printf '%s' "$?"
)"
assert_eq "an unreadable inventory exits 2" "2" "$(
  bash "$SUT" --inventory "$TEST_TMPDIR/absent.tsv" --sweep "$work/sweep.tsv" --out "$TEST_TMPDIR/x.md" >/dev/null 2>&1
  printf '%s' "$?"
)"

printf '\nPASS=%d FAIL=%d\n' "$((CASES - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
