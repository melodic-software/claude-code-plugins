#!/usr/bin/env bash
# Regression tests for pr-worktree.sh and the ready action's verify gate command that uses it: a
# session in the main checkout running `ready <pr>` for a PR built in a worktree checks the PR's
# tree and records that tree's HEAD. The gate command is extracted from the ready
# reference and run in a fixture repository against a stubbed `gh`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$SCRIPT_DIR/pr-worktree.sh"
REF="$SKILL_DIR/reference/ready-for-review.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

# A gh stand-in: the head read answers STUB_BRANCH and STUB_OID, and fails when STUB_FAIL is set.
STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
[[ -z "${STUB_FAIL:-}" ]] || exit 1
[[ "$1 $2" == "pr view" && " $* " == *" headRefName,headRefOid "* ]] || exit 99
echo "$STUB_BRANCH $STUB_OID"
STUB_EOF
chmod +x "$STUB_DIR/gh"
export PATH="$STUB_DIR:$PATH"

# Fixture: the main checkout on main, and the PR's branch in a linked worktree with one more
# commit. Each tree's scripts/check-affected.sh prints the files the checked tree changed since
# main and which tree it checked, so the gate output shows whose tree was checked. The stub takes
# that tree from CHECK_DATA_ROOT, else from the working directory, never from its own location, so
# the gate assertions fail unless the gate itself names the PR's tree.
MAIN="$TEST_TMPDIR/main"
git init -q -b main "$MAIN"
mkdir -p "$MAIN/scripts"
cat >"$MAIN/scripts/check-affected.sh" <<'EOF'
#!/usr/bin/env bash
top=$(git -C "${CHECK_DATA_ROOT:-$PWD}" rev-parse --show-toplevel) || exit 2
top=$(cd "$top" && pwd -P)
echo "checked $top"
git -C "$top" diff --name-only main HEAD | sed 's/^/changed: /'
EOF
git -C "$MAIN" add scripts/check-affected.sh
git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q -m base
MAIN_HEAD=$(git -C "$MAIN" rev-parse HEAD)
PR_WT="$TEST_TMPDIR/pr-tree"
git -C "$MAIN" worktree add -q -b feat/pr "$PR_WT"
echo change >"$PR_WT/feature.md"
git -C "$PR_WT" add feature.md
git -C "$PR_WT" -c user.name=t -c user.email=t@t commit -q -m feature
PR_HEAD=$(git -C "$PR_WT" rev-parse HEAD)
PR_WT_REAL=$(physical_dir "$PR_WT")
MAIN_REAL=$(physical_dir "$MAIN")
export STUB_BRANCH=feat/pr STUB_OID="$PR_HEAD"

out=$(cd "$MAIN" && bash "$SCRIPT" --pr 7)
assert_exit "from the main checkout: the PR's worktree is found" 0 "$?"
assert_eq "from the main checkout: the path is the PR's worktree" "$PR_WT_REAL" "$(physical_dir "$out")"

out=$(cd "$PR_WT" && bash "$SCRIPT" --pr 7)
assert_exit "from the PR's worktree: found" 0 "$?"
assert_eq "from the PR's worktree: its own top level comes back" "$PR_WT_REAL" "$(physical_dir "$out")"

out=$(cd "$MAIN" && STUB_BRANCH=main STUB_OID="$MAIN_HEAD" bash "$SCRIPT" --pr 7)
assert_eq "a branch the main checkout holds resolves to the main checkout" "$MAIN_REAL" "$(physical_dir "$out")"

out=$(cd "$PR_WT" && STUB_OID="$MAIN_HEAD" bash "$SCRIPT" --pr 7)
assert_eq "a worktree ahead of the PR's head commit (local commits not pushed yet) is still the PR's" "$PR_WT_REAL" "$(physical_dir "$out")"

out=$(cd "$MAIN" && STUB_BRANCH=main bash "$SCRIPT" --pr 7 2>&1)
assert_exit "a same-named branch without the PR's head commit (a fork's main) exits 2" 2 "$?"
assert_contains "the refusal names the missing head commit" "$out" "$PR_HEAD"

(cd "$MAIN" && STUB_OID=ffffffffffffffffffffffffffffffffffffffff bash "$SCRIPT" --pr 7 >/dev/null 2>&1)
assert_exit "a head commit this repository lacks exits 2" 2 "$?"
(cd "$MAIN" && STUB_OID=abc bash "$SCRIPT" --pr 7 >/dev/null 2>&1)
assert_exit "a malformed head commit exits 2" 2 "$?"

out=$(cd "$MAIN" && STUB_BRANCH=feat/elsewhere bash "$SCRIPT" --pr 7 2>&1)
assert_exit "a head branch checked out nowhere exits 2" 2 "$?"
assert_contains "the refusal names the branch" "$out" "'feat/elsewhere'"

out=$(cd "$MAIN" && STUB_BRANCH=feat bash "$SCRIPT" --pr 7 2>&1)
assert_exit "a branch name that is only a prefix of the checked-out one is not a match" 2 "$?"

(cd "$MAIN" && STUB_FAIL=1 bash "$SCRIPT" --pr 7 >/dev/null 2>&1)
assert_exit "a failed head-branch read exits 2" 2 "$?"
(cd "$MAIN" && STUB_BRANCH="" bash "$SCRIPT" --pr 7 >/dev/null 2>&1)
assert_exit "an empty head-branch read exits 2" 2 "$?"

bash "$SCRIPT" --pr abc >/dev/null 2>&1
assert_exit "a non-numeric --pr is a usage error" 1 "$?"
bash "$SCRIPT" >/dev/null 2>&1
assert_exit "a missing --pr is a usage error" 1 "$?"
bash "$SCRIPT" --pr 7 --pr 8 >/dev/null 2>&1
assert_exit "--pr given twice is a usage error" 1 "$?"
bash "$SCRIPT" --bogus >/dev/null 2>&1
assert_exit "an unknown argument is a usage error" 1 "$?"

# The verify gate command of the ready reference (2.5.3), run from the main checkout.
GATE=$(grep -F 'pr-worktree.sh" --pr' "$REF" | grep -F 'check-affected.sh" --tests' | sed -e 's/^ *//' -e "s#<skill-dir>#$SKILL_DIR#g")
if [[ -z "$GATE" ]]; then
  echo "FAIL: the verify gate command was not found in $REF" >&2
  exit 1
fi
export READY_VERIFY_DIR="$TEST_TMPDIR/verify"
out=$(cd "$MAIN" && PR_NUMBER=7 bash -c "$GATE" 2>&1)
assert_exit "the gate command from the main checkout succeeds" 0 "$?"
assert_contains "the gate checks the PR's worktree" "$out" "checked $PR_WT_REAL"
assert_contains "the gate output lists the PR's changed files" "$out" "changed: feature.md"
assert_eq "the gate records a pass for the PR worktree's HEAD" "pass" "$(cat "$READY_VERIFY_DIR/$PR_HEAD" 2>/dev/null)"
assert_file_absent "nothing is recorded for the main checkout's HEAD" "$READY_VERIFY_DIR/$MAIN_HEAD"

rm -rf "$READY_VERIFY_DIR"
out=$(cd "$MAIN" && STUB_BRANCH=feat/elsewhere PR_NUMBER=7 bash -c "$GATE" 2>&1)
assert_exit "the gate command for a head checked out nowhere fails" 1 "$?"
[[ -e "$READY_VERIFY_DIR" ]] && recorded=yes || recorded=no
assert_eq "the gate command for a head checked out nowhere records nothing" "no" "$recorded"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
