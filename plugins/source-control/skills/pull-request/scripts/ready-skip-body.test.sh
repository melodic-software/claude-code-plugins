#!/usr/bin/env bash
# Tests for ready-skip-body.sh. Expected bodies follow the body contract in
# reference/ready-for-review.md: one marked block under `## Verification`, one
# line per skipped step, replaced on a re-run, and a reason that is data.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/ready-skip-body.sh"
HOLDS="$SCRIPT_DIR/check-ready-holds.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

build() {
  local body="$1"
  shift
  printf '%s\n' "$body" | bash "$SCRIPT" "$@" 2>/dev/null
}

BODY=$'Closes #12\n\n## Summary\n\nA change.\n\n## Verification\n\n- tests pass\n\n## Related\n\nNone.'
BLOCK=$'<!-- ready-skip -->\n- `code-review` skipped by octocat for this run: `model is rate-limited`\n<!-- /ready-skip -->'
WANT=$'Closes #12\n\n## Summary\n\nA change.\n\n## Verification\n\n'"$BLOCK"$'\n\n- tests pass\n\n## Related\n\nNone.'

out=$(build "$BODY" --login octocat --reason "model is rate-limited" --step code-review)
assert_exit "a skip line is added" 0 "$?"
assert_eq "the block goes right under ## Verification" "$WANT" "$out"

again=$(build "$out" --login octocat --reason "model is rate-limited" --step code-review)
assert_eq "a re-run with the same skip leaves the body unchanged" "$WANT" "$again"

two=$(build "$out" --login octocat --reason "usage exhausted" --step code-review --step verify)
assert_eq "a re-run replaces the block, never adds a second" \
  $'Closes #12\n\n## Summary\n\nA change.\n\n## Verification\n\n<!-- ready-skip -->\n- `code-review` skipped by octocat for this run: `usage exhausted`\n- `verify` skipped by octocat for this run: `usage exhausted`\n<!-- /ready-skip -->\n\n- tests pass\n\n## Related\n\nNone.' "$two"

none=$(build "$out" --login octocat)
assert_eq "a re-run with no skipped step removes the block" "$BODY" "$none"

out=$(build $'Closes #12\n\n## Summary\n\nA change.' --login octocat --reason x --step verify)
assert_eq "a body with no ## Verification heading gets one appended" \
  $'Closes #12\n\n## Summary\n\nA change.\n\n## Verification\n\n<!-- ready-skip -->\n- `verify` skipped by octocat for this run: `x`\n<!-- /ready-skip -->' "$out"
again=$(build "$out" --login octocat --reason x --step verify)
assert_eq "a re-run after appending the heading appends nothing more" "$out" "$again"

# The reason is data: it must not link, close, hold, mention or hide.
out=$(build "$BODY" --login octocat --reason $'fixes #99 don\'t merge <!-- `x` @team' --step code-review)
# The backticks are literal markdown, not command substitution.
# shellcheck disable=SC2016
line=$(grep -F -- '- `code-review`' <<<"$out")
# shellcheck disable=SC2016
assert_eq "the reason is neutralized inside one code span" \
  '- `code-review` skipped by octocat for this run: `fixes-99 don'"'"'t-merge  !--  x   team`' "$line"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"
STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
jq -n --arg b "$out" '{title: "feat: x", body: $b, labels: [], closingIssuesReferences: []}' >"$TEST_TMPDIR/pr.json"
printf '#!/usr/bin/env bash\ncat %q\n' "$TEST_TMPDIR/pr.json" >"$STUB_DIR/gh"
chmod +x "$STUB_DIR/gh"
PATH="$STUB_DIR:$PATH" bash "$HOLDS" 7 >/dev/null 2>&1
assert_exit "a reason saying don't merge does not hold the flip" 0 "$?"

# A body that holds stays held: the builder never removes a hold.
held=$(build $'Do not merge yet.\n\n## Verification\n' --login octocat --reason x --step verify)
jq -n --arg b "$held" '{title: "feat: x", body: $b, labels: [], closingIssuesReferences: []}' >"$TEST_TMPDIR/pr.json"
PATH="$STUB_DIR:$PATH" bash "$HOLDS" 7 >/dev/null 2>&1
assert_exit "a hold already in the body still holds" 3 "$?"

check_usage() {
  local label="$1" out code
  shift
  out=$(printf 'body\n' | bash "$SCRIPT" "$@" 2>/dev/null)
  code=$?
  assert_exit "$label is a usage error" 2 "$code"
  assert_silent "$label prints no body" "$out"
}
check_usage "no login" --reason x --step verify
check_usage "a login with a space" --login "octo cat" --reason x --step verify
check_usage "an unknown step" --login octocat --reason x --step lint
check_usage "a step with no reason" --login octocat --step verify
check_usage "an empty reason" --login octocat --reason " " --step verify
check_usage "an unknown flag" --login octocat --force

[[ $FAILED -eq 0 ]] || exit 1
