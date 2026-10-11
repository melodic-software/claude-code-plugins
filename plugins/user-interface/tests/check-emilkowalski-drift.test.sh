#!/usr/bin/env bash
# Exit-code contract of scripts/check-emilkowalski-drift.sh, network-free: the
# script is sourced and fetch_tree is replaced by a stub. The expected SHAs are
# the upstream blob SHAs at pin 2d228630 recorded in
# docs/upstream/emilkowalski-skills.md, not values read from the script.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/../scripts/check-emilkowalski-drift.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() {
  case "$2" in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
    *"$3"*) fail "$1" "absent: $3" "$2" ;;
    *) pass "$1" ;;
  esac
}

# shellcheck source=../scripts/check-emilkowalski-drift.sh
source "$SCRIPT"

# The upstream tree at the pin, from docs/upstream/emilkowalski-skills.md.
PIN_TREE="57b46f1fd11dc62351ea548104a88aa3f659c11b LICENSE
3cc865e4f4d678c29dd938d11f96342942b7b52c README.md
5b279577685cebabbfbb0197bd6b3a74591b3392 performance-cheatsheet.md
a02e6b80f9dec86f196590f2f7a4fe3310ea1cb4 skills/animate-expo/RECIPES.md
78b39e1d22e8c3c15be96ccebe04bf39792f3455 skills/animate-expo/SKILL.md
6744891261bdf0bb0473d77f2cc706f2d78b574e skills/animate/RECIPES.md
7c3b20c6ed681b2d47c9ca9e3ee0e659ed47d032 skills/animate/SKILL.md
d688dd7c3ba143c6ae17efd2bc665380d5252c5a skills/animation-performance/SKILL.md
5ab2976514c74a194ebf069506d95ff3a5a0084f skills/animation-vocabulary/SKILL.md
adf68c517f2d7d2781587d619de07f4de286da57 skills/apple-design/SKILL.md
d2b0f3cf93d9495a8496275dc6e70199302df0f1 skills/ask-sonner/API.md
6cf9217f409315466ecfd7796de4591879983637 skills/ask-sonner/SKILL.md
46962bb89445b8526ea94994a79b49508573b5fd skills/break-ui/CATALOG.md
091a28d488662d2451131f1aaa60a6dcd2391932 skills/break-ui/SKILL.md
62ce902af8dd32c590ea7203e9ab2edb1d6ef81a skills/emil-design-eng/SKILL.md
d3b030fbca9abad9220a032f72d425c6b7fa2de8 skills/find-animation-opportunities/SKILL.md
94056154e532d695b8792ea67d701625b4f43b6e skills/improve-animations/AUDIT.md
239026b91f8032df191dde2085fd796b8c116d91 skills/improve-animations/PLAN-TEMPLATE.md
d6e77f37272329af0cc36f9eeedbe5226e86ce63 skills/improve-animations/SKILL.md
94bba21fcb990b850e06effbf5709c96a07446ad skills/mobile-native/SKILL.md
5e0028e988b88d2a88a019fdc978b4732243e467 skills/pick-ui-library/SKILL.md
aaa88c0eba38eb01c00d4eb2b144e39f808fc26a skills/prototype/PICKER.md
dbcc1a23c66933f7372c0aacbce2b0d7cc6100b6 skills/prototype/SKILL.md
577a64397267ce20960de2202950594d5bd6f9b6 skills/review-animations/SKILL.md
863ea12ea94c1f7a47b5f7e1019e976aa82bd4cd skills/review-animations/STANDARDS.md
a09a8f693304fe1c04ed56d61dde9833a516849e skills/write-swift/SKILL.md"
CHANGED_SHA=0123456789abcdef0123456789abcdef01234567

stub_tree="$PIN_TREE"
fetch_tree() { printf '%s\n' "$stub_tree"; }

# 1. Upstream at the pin.
out=$(run_check 2>&1)
code=$?
assert_eq "pin tree: exit 0" 0 "$code"
assert_contains "pin tree: reports no drift" "$out" "No drift"

# 2. A pinned file changed.
stub_tree="${PIN_TREE/d688dd7c3ba143c6ae17efd2bc665380d5252c5a/$CHANGED_SHA}"
out=$(run_check 2>&1)
code=$?
assert_eq "changed pinned file: exit 1" 1 "$code"
assert_contains "changed pinned file: names it" "$out" "CHANGED    skills/animation-performance/SKILL.md"
assert_contains "changed pinned file: shows the new SHA" "$out" "$CHANGED_SHA"
assert_not_contains "changed pinned file: LICENSE not flagged" "$out" "CHANGED    LICENSE"
assert_contains "changed pinned file: compare URL" "$out" \
  "https://github.com/emilkowalski/skills/compare/2d228630ba1446365f614a108cb8252f1feda202...main"

# 3. An omitted file changed: not drift.
stub_tree="${PIN_TREE/a09a8f693304fe1c04ed56d61dde9833a516849e/$CHANGED_SHA}"
out=$(run_check 2>&1)
code=$?
assert_eq "changed omitted file: exit 0" 0 "$code"

# 4. A pinned file is gone.
stub_tree="$(grep -v ' skills/break-ui/CATALOG.md$' <<<"$PIN_TREE")"
out=$(run_check 2>&1)
code=$?
assert_eq "pinned file gone: exit 1" 1 "$code"
assert_contains "pinned file gone: names it" "$out" "GONE       skills/break-ui/CATALOG.md"

# 5. A new upstream skill appears.
stub_tree="$PIN_TREE
$CHANGED_SHA skills/new-skill/SKILL.md"
out=$(run_check 2>&1)
code=$?
assert_eq "new upstream skill: exit 1" 1 "$code"
assert_contains "new upstream skill: names it" "$out" "NEW        skills/new-skill/SKILL.md"

# 6. A new file outside skills/ is not drift.
stub_tree="$PIN_TREE
$CHANGED_SHA docs/notes.md"
out=$(run_check 2>&1)
code=$?
assert_eq "new non-skill file: exit 0" 0 "$code"

# 7. The tree cannot be read.
fetch_tree() { return 1; }
out=$(run_check 2>&1)
code=$?
assert_eq "fetch failure: exit 2" 2 "$code"
assert_contains "fetch failure: says unverifiable" "$out" "Unverifiable"

# 8. parse_tree keeps a path containing spaces whole.
parsed=$(printf '100644 blob abc123\tskills/animate/SKILL.md x\n' | parse_tree)
assert_eq "parse_tree: spaced path kept whole" "abc123 skills/animate/SKILL.md x" "$parsed"

# 9. A spaced name beside a pinned path is new, and the pinned path stays found.
fetch_tree() { printf '%s\n' "$stub_tree"; }
stub_tree="$PIN_TREE
0123456789abcdef0123456789abcdef01234567 skills/animate/SKILL.md x"
out=$(run_check 2>&1)
code=$?
assert_eq "spaced new file: exit 1" 1 "$code"
assert_contains "spaced new file: reported whole" "$out" "NEW        skills/animate/SKILL.md x"
assert_not_contains "spaced new file: pinned path not gone" "$out" "GONE       skills/animate/SKILL.md "

# 10. A pinned path replaced by a spaced variant is gone, not unchanged.
animate_sha=$(awk '$2 == "skills/animate/SKILL.md" { print $1 }' <<<"$PIN_TREE")
stub_tree="$(grep -vF " skills/animate/SKILL.md" <<<"$PIN_TREE")
$animate_sha skills/animate/SKILL.md x"
out=$(run_check 2>&1)
assert_contains "spaced rename: pinned path reported gone" "$out" "GONE       skills/animate/SKILL.md"

# 11. Command line.
bash "$SCRIPT" --help >/dev/null 2>&1
assert_eq "--help: exit 0" 0 "$?"
bash "$SCRIPT" --bogus >/dev/null 2>&1
assert_eq "unknown mode: exit 2" 2 "$?"

if ((FAILED)); then
  printf '\n%d check(s) failed.\n' "$FAILED" >&2
  exit 1
fi
printf '\nAll checks passed.\n'
