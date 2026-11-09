#!/usr/bin/env bash
# Regression tests for reassess-comment.sh, including that no output reads as a
# member's veto under the merge gate's own pattern.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/reassess-comment.sh"
BABYSIT="$SCRIPT_DIR/../../babysit-prs/scripts"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

out=$(bash "$SCRIPT" --verdict close --replaced-by '#12' --evidence abc1234 --evidence 'https://github.com/a/b/pull/12')
assert_exit "a close renders" 0 "$?"
assert_contains "a close starts with the marker" "$(head -1 <<<"$out")" "<!-- source-control-reassess -->"
assert_contains "a close names what replaced it" "$out" "Replaced by #12."
assert_contains "a close lists its evidence" "$out" "- https://github.com/a/b/pull/12"
assert_contains "a close says the label holds it" "$out" "label now holds"
close_body="$out"

out=$(bash "$SCRIPT" --verdict close --replaced-by '#12' --no-label --evidence abc1234)
assert_exit "a close with no label renders" 0 "$?"
assert_not_contains "a close with no label claims no hold" "$out" "holds"
assert_contains "a close with no label still names the replacement" "$out" "Replaced by #12."

out=$(bash "$SCRIPT" --verdict rework --evidence '#3')
assert_exit "a rework renders" 0 "$?"
assert_not_contains "a rework names no label" "$out" "do-not-merge"
rework_body="$out"

if command -v python3 >/dev/null 2>&1; then
  for body in "$close_body" "$rework_body"; do
    python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1])
import babysit_merge
sys.exit(1 if babysit_merge.HUMAN_MERGE_VETO_RE.search(sys.argv[2]) else 0)' "$BABYSIT" "$body"
    assert_exit "the comment is no veto under the merge gate's pattern" 0 "$?"
  done
fi

for bad in '@someone' 'see /tmp/local/x' '#12 @x' 'https://evil.example/x' $'abc1234\nextra' 'do not merge'; do
  out=$(bash "$SCRIPT" --verdict rework --evidence "$bad" 2>/dev/null)
  assert_exit "a free-text evidence value is refused: ${bad%%$'\n'*}" 2 "$?"
  assert_silent "a refused value prints nothing" "$out"
done

bash "$SCRIPT" --verdict close --evidence '#3' >/dev/null 2>&1
assert_exit "a close with no replacement is refused" 2 "$?"
bash "$SCRIPT" --verdict rework --replaced-by '#4' --evidence '#3' >/dev/null 2>&1
assert_exit "a rework with a replacement is refused" 2 "$?"
bash "$SCRIPT" --verdict continue --evidence '#3' >/dev/null 2>&1
assert_exit "continue posts no comment" 2 "$?"
bash "$SCRIPT" --verdict rework >/dev/null 2>&1
assert_exit "a comment with no evidence is refused" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
