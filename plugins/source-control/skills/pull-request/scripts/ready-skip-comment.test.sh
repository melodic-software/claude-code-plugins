#!/usr/bin/env bash
# Tests for ready-skip-comment.sh. Expected comments follow the skip-record
# contract in reference/ready-for-review.md: a marker line naming the head,
# then one line per skipped step in run order, with the reason as inert data.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/ready-skip-comment.sh"
HOLDS="$SCRIPT_DIR/check-ready-holds.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

HEAD=0123456789abcdef0123456789abcdef01234567
build() { bash "$SCRIPT" --login octocat --head "$HEAD" "$@" 2>/dev/null; }

# The backticks below are literal markdown, not command substitution.
# shellcheck disable=SC2016
WANT=$'<!-- ready-skip head=0123456789abcdef0123456789abcdef01234567 -->\n- `code-review` skipped by octocat for this run: `model is rate-limited`'
out=$(build --reason "model is rate-limited" --step code-review)
assert_exit "one skipped step builds a comment" 0 "$?"
assert_eq "the comment is the head marker, then the step line" "$WANT" "$out"

# shellcheck disable=SC2016
out=$(build --reason "usage exhausted" --step verify --step base-merge)
assert_eq "several steps are listed in run order" \
  $'<!-- ready-skip head=0123456789abcdef0123456789abcdef01234567 -->\n- `base-merge` skipped by octocat for this run: `usage exhausted`\n- `verify` skipped by octocat for this run: `usage exhausted`' "$out"

# The reason is data: it must not link, close, hold, mention or hide.
out=$(build --reason $'fixes #99 don\'t merge <!-- `x` @team\nnext' --step code-review)
# shellcheck disable=SC2016
assert_eq "the reason is neutralized inside one code span" \
  $'<!-- ready-skip head=0123456789abcdef0123456789abcdef01234567 -->\n- `code-review` skipped by octocat for this run: `fixes-99 don\'t-merge  !--  x   team next`' "$out"
out=$(build --reason "Closes: 4, resolved 5, Do Not   merge" --step verify)
assert_contains "each closing keyword and the hold phrase are broken, in any case" "$out" \
  "Closes-4, resolved-5, Do Not-merge"

# The neutralized comment, read as a PR body, holds nothing; a real hold still holds.
command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"
STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
printf '#!/usr/bin/env bash\ncat %q\n' "$TEST_TMPDIR/pr.json" >"$STUB_DIR/gh"
chmod +x "$STUB_DIR/gh"
holds() {
  jq -n --arg b "$1" '{title: "feat: x", body: $b, labels: [], closingIssuesReferences: []}' >"$TEST_TMPDIR/pr.json"
  PATH="$STUB_DIR:$PATH" bash "$HOLDS" 7 >/dev/null 2>&1
}
holds "$(build --reason "don't merge, do not merge" --step verify)"
assert_exit "a reason naming the hold phrase holds nothing" 0 "$?"
holds "Do not merge yet."
assert_exit "the hold phrase itself, unsanitized, holds" 3 "$?"

check_usage() {
  local label="$1" out code
  shift
  out=$(bash "$SCRIPT" "$@" 2>/dev/null)
  code=$?
  assert_exit "$label is a usage error" 2 "$code"
  assert_silent "$label prints no comment" "$out"
}
check_usage "no step" --login octocat --head "$HEAD" --reason x
check_usage "no login" --head "$HEAD" --reason x --step verify
check_usage "a login with a space" --login "octo cat" --head "$HEAD" --reason x --step verify
check_usage "no head" --login octocat --reason x --step verify
check_usage "a short head" --login octocat --head abc123 --reason x --step verify
check_usage "an unknown step" --login octocat --head "$HEAD" --reason x --step lint
check_usage "a step with no reason" --login octocat --head "$HEAD" --step verify
check_usage "an empty reason" --login octocat --head "$HEAD" --reason " " --step verify
check_usage "an unknown flag" --login octocat --head "$HEAD" --reason x --step verify --force

[[ $FAILED -eq 0 ]] || exit 1
