#!/usr/bin/env bash
# Exit-code contract of scripts/check-emilkowalski-drift.sh, network-free: the
# script is sourced and fetch_tree is replaced by a stub. The expected SHAs are
# the upstream blob SHAs at pin c8a79627 recorded in
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
PIN_TREE="a0652a605e6b418261a2b4fb1ad82576be0c3b53 .gitattributes
e43b0f988953ae3a84b00331d0ccf5f7d51cb3cf .gitignore
e69de29bb2d1d6434b8b29ae775ad8c2e48c5391 .pl
57b46f1fd11dc62351ea548104a88aa3f659c11b LICENSE
e77e3dbb87c3349e323cbebd46d91fd7dbdc5b1b README.md
15f73d24a3b0e8a44d96d16d996719565b3ab7d5 performance-cheatsheet.md
a5c803280b82f72dd11ed2136caaf0ea8c139a5c ui-cheatsheet.md
a02e6b80f9dec86f196590f2f7a4fe3310ea1cb4 skills/animate-expo/RECIPES.md
78b39e1d22e8c3c15be96ccebe04bf39792f3455 skills/animate-expo/SKILL.md
6744891261bdf0bb0473d77f2cc706f2d78b574e skills/animate/RECIPES.md
2d3b63acc5e2afcbf54b5ba59792e69fa51bcb0d skills/animate/SKILL.md
74c421e4e673cab84490f8b17b89735c30b0f555 skills/animation-performance/SKILL.md
5ab2976514c74a194ebf069506d95ff3a5a0084f skills/animation-vocabulary/SKILL.md
adf68c517f2d7d2781587d619de07f4de286da57 skills/apple-design/SKILL.md
d2b0f3cf93d9495a8496275dc6e70199302df0f1 skills/ask-sonner/API.md
6cf9217f409315466ecfd7796de4591879983637 skills/ask-sonner/SKILL.md
46962bb89445b8526ea94994a79b49508573b5fd skills/break-ui/CATALOG.md
091a28d488662d2451131f1aaa60a6dcd2391932 skills/break-ui/SKILL.md
17936a9cfc3e26224c5b4555f5a239758718815c skills/choreograph/RECIPES.md
9fef0048d260be7bc05a909a03b52627bb3ccf37 skills/choreograph/SKILL.md
dc063c2a861922c1c9f2412b824b0862746304f5 skills/emil-design-eng/SKILL.md
d3b030fbca9abad9220a032f72d425c6b7fa2de8 skills/find-animation-opportunities/SKILL.md
0862c446eea250326cdd2054fc3492c6707f4cf7 skills/improve-animations/AUDIT.md
239026b91f8032df191dde2085fd796b8c116d91 skills/improve-animations/PLAN-TEMPLATE.md
d6e77f37272329af0cc36f9eeedbe5226e86ce63 skills/improve-animations/SKILL.md
94bba21fcb990b850e06effbf5709c96a07446ad skills/mobile-native/SKILL.md
5e0028e988b88d2a88a019fdc978b4732243e467 skills/pick-ui-library/SKILL.md
aaa88c0eba38eb01c00d4eb2b144e39f808fc26a skills/prototype/PICKER.md
dbcc1a23c66933f7372c0aacbce2b0d7cc6100b6 skills/prototype/SKILL.md
100b7b7666f7d09c69a75ebb793e30e607058e77 skills/remove-animations/SKILL.md
591397b5308266f76671dacc3e44830a3e3e535f skills/review-animations/SKILL.md
67b6edb5ed45aeafe7e3706bb76e27f3bd209a92 skills/review-animations/STANDARDS.md
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
stub_tree="${PIN_TREE/74c421e4e673cab84490f8b17b89735c30b0f555/$CHANGED_SHA}"
out=$(run_check 2>&1)
code=$?
assert_eq "changed pinned file: exit 1" 1 "$code"
assert_contains "changed pinned file: names it" "$out" "CHANGED    skills/animation-performance/SKILL.md"
assert_contains "changed pinned file: shows the new SHA" "$out" "$CHANGED_SHA"
assert_not_contains "changed pinned file: LICENSE not flagged" "$out" "CHANGED    LICENSE"
assert_contains "changed pinned file: compare URL" "$out" \
  "https://github.com/emilkowalski/skills/compare/c8a79627b59d72d764d6ab6f2c87c09a48169833...main"

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

# 6. A new file in another directory is not drift.
stub_tree="$PIN_TREE
$CHANGED_SHA docs/notes.md"
out=$(run_check 2>&1)
code=$?
assert_eq "new file in another directory: exit 0" 0 "$code"

# 6b. A new root file is drift, and a known omitted root file is not.
stub_tree="$PIN_TREE
$CHANGED_SHA new-cheatsheet.md"
out=$(run_check 2>&1)
code=$?
assert_eq "new root file: exit 1" 1 "$code"
assert_contains "new root file: names it" "$out" "NEW        new-cheatsheet.md"
assert_not_contains "new root file: README not flagged" "$out" "NEW        README.md"

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
