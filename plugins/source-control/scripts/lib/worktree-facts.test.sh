#!/usr/bin/env bash
# Fact-record tests. Assertion helpers are local.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_COMMON_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=worktree-facts.sh
source "$SCRIPT_DIR/worktree-facts.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0
CASE_NUM=0
EXPECTED_CASES=21

pass() { CASE_NUM=$((CASE_NUM + 1)); printf 'PASS: %s\n' "$1"; }
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi; }

git init -q "$TEST_TMPDIR/repo"
git -C "$TEST_TMPDIR/repo" config user.email t@example.com
git -C "$TEST_TMPDIR/repo" config user.name Test
printf 'x\n' >"$TEST_TMPDIR/repo/f"
git -C "$TEST_TMPDIR/repo" add f
git -C "$TEST_TMPDIR/repo" commit -q -m init

# Helper-created and locked.
git -C "$TEST_TMPDIR/repo" worktree add -q "$TEST_TMPDIR/helper" -b helper
helper_reason="$(HOSTNAME=testhost worktree_lock_reason worktree-create.sh sess-owner)"
git -C "$TEST_TMPDIR/repo" worktree lock --reason "$helper_reason" "$TEST_TMPDIR/helper"
por="$TEST_TMPDIR/list.z"
git -C "$TEST_TMPDIR/repo" worktree list --porcelain -z >"$por"
worktree_facts_parse_z "$por"
assert_eq "helper lock: reason round-trips through porcelain" "${WT_FACT_LOCKED[1]}" "$helper_reason"
if worktree_reason_is_ours "${WT_FACT_LOCKED[1]}" sess-owner; then
  pass "helper lock: check-enter token matches the creator"
else
  fail "helper lock: check-enter token matches the creator" "ours" "${WT_FACT_LOCKED[1]}"
fi
assert_eq "helper lock: the added worktree is linked" "${WT_FACT_LINKED[1]}" "yes"
assert_eq "main checkout is not linked" "${WT_FACT_LINKED[0]}" "no"

# Added bare, then claimed.
git -C "$TEST_TMPDIR/repo" worktree add -q "$TEST_TMPDIR/plain" -b plain
claim_reason="$(HOSTNAME=testhost worktree_lock_reason worktree-claim.sh sess-claim)"
git -C "$TEST_TMPDIR/repo" worktree lock --reason "$claim_reason" "$TEST_TMPDIR/plain"
git -C "$TEST_TMPDIR/repo" worktree list --porcelain -z >"$por"
worktree_facts_parse_z "$por"
plain_reason=""
for i in "${!WT_FACT_PATH[@]}"; do
  [[ "${WT_FACT_PATH[$i]}" == "$TEST_TMPDIR/plain" ]] && plain_reason="${WT_FACT_LOCKED[$i]}"
done
assert_eq "claimed after a bare add: the claim written is the claim read" "$plain_reason" "$claim_reason"
if worktree_reason_is_ours "$plain_reason" sess-other; then
  fail "foreign session is not the owner" "not ours" "$plain_reason"
else
  pass "foreign session is not the owner"
fi

# `-z` emits the lock reason raw: quotes and backslash sequences are text, not escapes.
quoted_reason='"quoted reason"'
backslash_reason='a\nb\\c'
git -C "$TEST_TMPDIR/repo" worktree add -q "$TEST_TMPDIR/quoted" -b quoted
git -C "$TEST_TMPDIR/repo" worktree lock --reason "$quoted_reason" "$TEST_TMPDIR/quoted"
git -C "$TEST_TMPDIR/repo" worktree add -q "$TEST_TMPDIR/backslash" -b backslash
git -C "$TEST_TMPDIR/repo" worktree lock --reason "$backslash_reason" "$TEST_TMPDIR/backslash"
list_out="$(bash "$SCRIPT_DIR/worktree-facts.sh" list "$TEST_TMPDIR/repo")"
git -C "$TEST_TMPDIR/repo" worktree list --porcelain -z >"$por"
worktree_facts_parse_z "$por"
quoted_got="" backslash_got=""
for i in "${!WT_FACT_PATH[@]}"; do
  [[ "${WT_FACT_PATH[$i]}" == "$TEST_TMPDIR/quoted" ]] && quoted_got="${WT_FACT_LOCKED[$i]}"
  [[ "${WT_FACT_PATH[$i]}" == "$TEST_TMPDIR/backslash" ]] && backslash_got="${WT_FACT_LOCKED[$i]}"
done
assert_eq "a reason wrapped in double quotes round-trips unchanged" "$quoted_got" "$quoted_reason"
assert_eq "a literal backslash-n and backslash pair round-trip unchanged" "$backslash_got" "$backslash_reason"
assert_eq "list prints the raw quoted reason in the lock_reason column" \
  "$(awk -F'\t' -v p="$TEST_TMPDIR/quoted" '$1 == p { print $7 }' <<<"$list_out")" "$quoted_reason"
assert_eq "list prints the raw backslash reason in the lock_reason column" \
  "$(awk -F'\t' -v p="$TEST_TMPDIR/backslash" '$1 == p { print $7 }' <<<"$list_out")" "$backslash_reason"

# Bare hub.
git init --bare -q "$TEST_TMPDIR/hub.git"
git -C "$TEST_TMPDIR/hub.git" worktree list --porcelain -z >"$por"
worktree_facts_parse_z "$por"
assert_eq "bare hub: the record is bare and has no HEAD" "${WT_FACT_BARE[0]}|${WT_FACT_HEAD[0]}" "yes|"

# Path absent and notgit are row states: empty columns stay in place.
row="$(worktree_fact_row "/gone" "" "" "?" "?" "none" "" "?" "?" "?" "?" "?" "" "notgit" "path-absent")"
# shellcheck disable=SC2034
IFS=$'\t' read -r path branch head unpushed landed method base inprogress staged unstaged conflicted untracked peers risk reason <<<"$row"
assert_eq "path-absent: risk and reason keep their columns" "$risk|$reason" "notgit|path-absent"
assert_eq "path-absent: an empty HEAD is a dash, not a missing column" "$head" "-"

# A new column cannot shift risk. The extra field is inserted before risk.
row2="$(worktree_fact_row "/gone" "" "" "?" "?" "none" "" "?" "?" "?" "?" "?" "" "EXTRA" "notgit" "path-absent")"
# shellcheck disable=SC2034
IFS=$'\t' read -r _p _b _h _u _l _m _base _ip _st _us _cf _ut _peers extra risk2 reason2 <<<"$row2"
assert_eq "a new column stays a dash-or-value and does not move risk" "$extra|$risk2|$reason2" "EXTRA|notgit|path-absent"

# notgit row, same schema, reason in its own column.
row3="$(worktree_fact_row "/notgit" "" "" "?" "?" "none" "" "?" "?" "?" "?" "?" "" "notgit" "not-a-worktree-root")"
# shellcheck disable=SC2034
IFS=$'\t' read -r _p _b _h _u _l _m _base _ip _st _us _cf _ut _peers risk3 reason3 <<<"$row3"
assert_eq "notgit: reason is its own column" "$risk3|$reason3" "notgit|not-a-worktree-root"

encoder="$(grep -Rnl 'lane active on %s' "$SCRIPT_DIR/.." --include='*.sh' | grep -v '\.test\.sh$' | xargs -n1 realpath)"
assert_eq "lock-reason text has one home" "$encoder" "$(realpath "$SCRIPT_DIR/worktree-facts.sh")"
parse_home="$(grep -Rnl 'line#worktree ' "$SCRIPT_DIR/.." --include='*.sh' | grep -v '\.test\.sh$' | xargs -n1 realpath)"
assert_eq "porcelain parse has one home" "$parse_home" "$(realpath "$SCRIPT_DIR/worktree-facts.sh")"

# A reasonless lock is still a lock, and `list` prints it.
git -C "$TEST_TMPDIR/repo" worktree add -q "$TEST_TMPDIR/bare-lock" -b bare-lock
git -C "$TEST_TMPDIR/repo" worktree lock "$TEST_TMPDIR/bare-lock"
listed="$(bash "$SCRIPT_DIR/worktree-facts.sh" list "$TEST_TMPDIR/repo" | awk -F'\t' -v p="$TEST_TMPDIR/bare-lock" '$1 == p {print $6 "|" $7}')"
assert_eq "list: a reasonless lock reads locked=yes, lock_reason=-" "$listed" "yes|-"

# The session parser reads what the encoder writes, and only that.
assert_eq "reason_lane: host and session id come back" "$(worktree_reason_lane "$helper_reason")" "testhost sess-owner"
no_session_reason="$(HOSTNAME=testhost worktree_lock_reason worktree-create.sh)"
if worktree_reason_lane "$no_session_reason" >/dev/null; then
  fail "reason_lane: a session-less reason has no lane" "no match" "$no_session_reason"
else
  pass "reason_lane: a session-less reason has no lane"
fi
if worktree_reason_lane "unlock when done" >/dev/null; then
  fail "reason_lane: free text has no lane" "no match" "match"
else
  pass "reason_lane: free text has no lane"
fi

echo "---"
if [[ "$FAILED" -eq 0 && "$CASE_NUM" -eq "$EXPECTED_CASES" ]]; then
  echo "OK ($CASE_NUM cases)"
  exit 0
fi
echo "FAILED=$FAILED CASES=$CASE_NUM EXPECTED=$EXPECTED_CASES" >&2
exit 1
