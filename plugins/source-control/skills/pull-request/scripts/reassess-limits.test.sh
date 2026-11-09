#!/usr/bin/env bash
# Regression tests for reassess-limits.sh, black-box with a stubbed `gh` on PATH
# and a real git repository for the worktree claims.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/reassess-limits.sh"
BABYSIT="$SCRIPT_DIR/../../babysit-prs/scripts"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

STUB_DIR="$TEST_TMPDIR/stubs"
F="$TEST_TMPDIR/forge"
mkdir -p "$STUB_DIR" "$F"
# Each read answers from a raw API-shaped file under $F, through any --jq the
# script passed, so the script's own filters run; a missing file fails the read.
cat >"$STUB_DIR/gh" <<STUB_EOF
#!/usr/bin/env bash
file=""
case "\$*" in
  "pr view"*) file=pr ;;
  "pr list"*) file=same-head ;;
  "api graphql"*) file=queue ;;
  *issues/*/comments*) file=comments ;;
  *pulls/*/reviews*) file=reviews ;;
  *pulls/*/comments*) file=inline ;;
  *repos/*/pulls/*) file=stack ;;
esac
[[ -n "\$file" && -f "$F/\$file" ]] || exit 1
filter=""
while (( \$# > 0 )); do
  [[ "\$1" == --jq ]] && filter="\$2"
  shift
done
if [[ -n "\$filter" ]]; then jq -r "\$filter" "$F/\$file"; else cat "$F/\$file"; fi
STUB_EOF
chmod +x "$STUB_DIR/gh"

REPO_DIR="$TEST_TMPDIR/repo"
export GIT_CONFIG_GLOBAL="$TEST_TMPDIR/gitconfig" GIT_CONFIG_NOSYSTEM=1
: >"$GIT_CONFIG_GLOBAL"
git init -q -b main "$REPO_DIR"
git -C "$REPO_DIR" config user.email t@example.invalid
git -C "$REPO_DIR" config user.name t
git -C "$REPO_DIR" commit -q --allow-empty -m seed
git -C "$REPO_DIR" branch feat/x
STATE="$TEST_TMPDIR/state"
mkdir -p "$STATE/active-workers"
LEASE="$STATE/active-workers/acme__app__pr-7.json"

# pr [state] [body] [labels-json] [cross]
pr() {
  jq -n --arg s "${1:-OPEN}" --arg b "${2:-}" --argjson l "${3:-[]}" --argjson c "${4:-false}" \
    '{state: $s, body: $b, labels: $l, isCrossRepository: $c, headRefName: "feat/x", headRefOid: "abc",
      headRepositoryOwner: {login: "acme"}}' >"$F/pr"
}

queued() { printf '{"data":{"repository":{"pullRequest":{"isInMergeQueue":%s}}}}' "$1" >"$F/queue"; }

reset() {
  pr
  queued false
  echo '{}' >"$F/stack"
  echo '[{"headRepositoryOwner":{"login":"acme"}}]' >"$F/same-head"
  echo '[[]]' >"$F/comments"
  echo '[[]]' >"$F/reviews"
  echo '[[]]' >"$F/inline"
  rm -f "$LEASE"
}

run() {
  (cd "$REPO_DIR" && PATH="$STUB_DIR:$PATH" CLAUDE_CODE_SESSION_ID=this-session bash "$SCRIPT" 7 --repo acme/app --state-dir "$STATE" "$@")
}

reset
out=$(run)
assert_exit "no limit exits 0" 0 "$?"
assert_silent "no limit prints nothing" "$out"

pr MERGED
out=$(run)
assert_exit "a merged pull request is refused" 4 "$?"
assert_contains "the refusal names the state" "$out" "refused: the pull request is MERGED"

reset
pr OPEN "" '[{"name":"Do-Not-Merge"}]'
out=$(run)
assert_exit "the label is a limit" 3 "$?"
assert_contains "the label limit is reported in any case" "$out" "label: "

reset
pr OPEN $'## Summary\nHold: waiting on the evals'
out=$(run)
assert_exit "a Hold: body line is a limit" 3 "$?"
assert_contains "a Hold: line reads as held" "$out" "held: its body"

reset
pr OPEN $'## Summary\n Hold: waiting'
out=$(run)
assert_contains "a Hold: line behind a no-break space holds" "$out" "held: its body"

reset
pr OPEN $'## Summary\rhold: waiting'
out=$(run)
assert_contains "a Hold: line after a bare carriage return holds" "$out" "held: its body"

reset
pr OPEN "Please don't merge this yet"
out=$(run)
assert_contains "a body saying not to merge reads as held" "$out" "held: its body"

reset
pr OPEN "This threshold: mentions hold: mid-line"
out=$(run)
assert_exit "hold: in the middle of a line holds nothing" 0 "$?"

reset
queued true
out=$(run)
assert_contains "a queued pull request is limited" "$out" "queue: "

reset
echo '{"stack":{"id":1}}' >"$F/stack"
out=$(run)
assert_contains "a stack member is limited" "$out" "stack: "

for read in queue stack comments reviews inline same-head; do
  reset
  rm "$F/$read"
  out=$(run)
  assert_exit "a failed $read read is a limit, not a pass" 3 "$?"
  assert_contains "a failed $read read reads as unread" "$out" "unread: "
done

reset
echo 'null' >"$F/queue"
out=$(run)
assert_contains "a junk queue answer reads as unread" "$out" "unread: its merge queue"

reset
rm "$F/pr"
out=$(run)
assert_exit "a failed pull request read is a limit" 3 "$?"
assert_contains "a failed pull request read reads as unread" "$out" "unread: the pull request"

comment() {
  printf '{"user":{"login":"%s","type":"%s"},"author_association":"%s","created_at":"%s","body":"%s"}' "$1" "$2" "$3" "$4" "$5"
}

review() {
  printf '{"user":{"login":"%s","type":"User"},"author_association":"MEMBER","submitted_at":"%s","state":"%s","body":"%s"}' "$1" "$2" "$3" "${4:-}"
}

reset
echo "[[$(comment ana User MEMBER 2026-01-01T00:00:00Z 'do not merge')]]" >"$F/comments"
out=$(run)
assert_contains "a member's veto holds" "$out" "held: a veto from ana"

reset
echo "[[$(review ana 2026-01-01T00:00:00Z COMMENTED 'do not merge')]]" >"$F/reviews"
out=$(run)
assert_contains "a veto in a review body holds" "$out" "held: a veto from ana"

reset
echo "[[$(comment ana User MEMBER 2026-01-01T00:00:00Z 'do not merge')]]" >"$F/inline"
out=$(run)
assert_contains "a veto in an inline comment holds" "$out" "held: a veto from ana"

reset
echo "[[$(comment ana User MEMBER 2026-01-01T00:00:00Z 'do not merge'),$(comment ana User MEMBER 2026-01-02T00:00:00Z 'fine now')]]" >"$F/comments"
out=$(run)
assert_exit "a member's later comment lifts their veto" 0 "$?"

reset
echo "[[$(comment ana User MEMBER 2026-01-01T00:00:00Z 'do not merge'),$(comment ana User MEMBER 2026-01-02T00:00:00Z '  ')]]" >"$F/comments"
out=$(run)
assert_contains "a later empty item lifts nothing" "$out" "held: a veto from ana"

reset
echo "[[$(comment zed User NONE 2026-01-01T00:00:00Z 'do not merge')]]" >"$F/comments"
out=$(run)
assert_exit "an outsider's comment is no veto" 0 "$?"

reset
echo "[[$(comment bot Bot MEMBER 2026-01-01T00:00:00Z 'do not merge')]]" >"$F/comments"
out=$(run)
assert_exit "a bot's comment is no veto" 0 "$?"

reset
echo "[[$(comment ana User MEMBER 2026-01-01T00:00:00Z 'see the do-not-merge label')]]" >"$F/comments"
out=$(run)
assert_exit "naming the label as a label is no veto" 0 "$?"

reset
# shellcheck disable=SC2016 # literal backticks
echo "[[$(comment ana User MEMBER 2026-01-01T00:00:00Z 'see the `do-not-merge` label')]]" >"$F/comments"
out=$(run)
assert_exit "naming the backticked label as a label is no veto" 0 "$?"

reset
echo "[[$(comment ana User MEMBER 2026-01-01T00:00:00Z 'do-not-merge, please')]]" >"$F/comments"
out=$(run)
assert_contains "a bare do-not-merge is a veto" "$out" "held: a veto from ana"

reset
echo "[[$(review ana 2026-01-01T00:00:00Z CHANGES_REQUESTED)]]" >"$F/reviews"
out=$(run)
assert_contains "an outstanding change request stops an update" "$out" "no-update: changes requested by ana"

reset
echo "[[$(review ana 2026-01-01T00:00:00Z CHANGES_REQUESTED),$(review ana 2026-01-02T00:00:00Z APPROVED)]]" >"$F/reviews"
out=$(run)
assert_exit "a later approval clears the change request" 0 "$?"

reset
pr OPEN "" "[]" true
out=$(run)
assert_exit "a fork head is a limit" 3 "$?"
assert_contains "a fork head stops an update" "$out" "no-update: the head is on a fork"

reset
echo '[{"headRepositoryOwner":{"login":"acme"}},{"headRepositoryOwner":{"login":"ACME"}}]' >"$F/same-head"
out=$(run)
assert_contains "a head branch two pull requests share stops an update" "$out" "no-update: its head branch"

reset
echo '[{"headRepositoryOwner":{"login":"acme"}},{"headRepositoryOwner":{"login":"fork-owner"}}]' >"$F/same-head"
out=$(run)
assert_exit "a fork's same-named head does not make it shared" 0 "$?"

reset
pr OPEN "" '[{"name":"standards-sync"}]'
out=$(run)
assert_contains "the standards-sync label stops an update" "$out" "no-update: it carries"

reset
out=$(run --expect-head other)
assert_contains "a moved head is a limit" "$out" "moved: "
out=$(run --expect-head abc)
assert_exit "the expected head is no limit" 0 "$?"

reset
echo '{"expires_at":"2099-01-01T00:00:00+00:00"}' >"$LEASE"
out=$(run)
assert_contains "a live lease holds" "$out" "held: a live babysit worker lease"

echo '{"expires_at":"2020-01-01T00:00:00.123456+00:00"}' >"$LEASE"
out=$(run)
assert_exit "an expired lease holds nothing" 0 "$?"

echo '{"holder":"x"}' >"$LEASE"
out=$(run)
assert_contains "a lease with no expiry reads as unread" "$out" "unread: the babysit worker lease"

echo 'not json' >"$LEASE"
out=$(run)
assert_contains "an unparsable lease reads as unread" "$out" "unread: the babysit worker lease"

if command -v python3 >/dev/null 2>&1; then
  # The patterns and the lease path are babysit-prs'; these fail when either moves.
  gate() {
    python3 -I -c 'import sys
sys.path.insert(0, sys.argv[1])
import babysit_lease, babysit_merge, babysit_merge_policy
print(babysit_merge_policy.BODY_MERGE_HOLD_RE.pattern)
print(babysit_merge.HUMAN_MERGE_VETO_RE.pattern)
print(babysit_lease.lease_path(sys.argv[2], "worker", "Acme/App#7"))' "$BABYSIT" "$STATE"
  }
  { read -r body_re; read -r veto_re; read -r lease_file; } < <(gate)
  eval "$(grep -E '^(BODY_HOLD_RE|VETO_RE)=' "$SCRIPT")"
  # shellcheck disable=SC2153,SC2154 # assigned by the eval above
  assert_eq "the body hold pattern is the merge gate's" "$body_re" "$BODY_HOLD_RE"
  # shellcheck disable=SC2153,SC2154 # assigned by the eval above
  assert_eq "the veto pattern is the merge gate's" "$veto_re" "$VETO_RE"
  reset
  echo '{"expires_at":"2099-01-01T00:00:00+00:00"}' >"$lease_file"
  out=$(cd "$REPO_DIR" && PATH="$STUB_DIR:$PATH" bash "$SCRIPT" 7 --repo Acme/App --state-dir "$STATE")
  assert_contains "a mixed-case repository finds the file babysit writes" "$out" "held: a live babysit worker lease"
  rm -f "$lease_file"
fi

reset
out=$(cd "$REPO_DIR" && PATH="$STUB_DIR:$PATH" bash "$SCRIPT" 7 --repo acme/app)
assert_exit "no state directory is a limit" 3 "$?"
assert_contains "no state directory reads as unread" "$out" "unread: the babysit worker lease"

reset
git -C "$REPO_DIR" worktree add -q "$TEST_TMPDIR/linked" feat/x
out=$(run)
assert_exit "an unclaimed worktree on the head is a limit" 3 "$?"
assert_contains "an unclaimed worktree reads as held" "$out" "unclaimed"

git -C "$REPO_DIR" worktree lock --reason "worktree-create.sh: lane active on $(hostname) session other-session since 2026-01-01T00:00:00Z; unlock when the owning lane is done" "$TEST_TMPDIR/linked"
out=$(run)
assert_contains "another session's claim holds" "$out" "another live session"
git -C "$REPO_DIR" worktree unlock "$TEST_TMPDIR/linked"

git -C "$REPO_DIR" worktree lock --reason "worktree-create.sh: lane active on $(hostname) session this-session since 2026-01-01T00:00:00Z; unlock when the owning lane is done" "$TEST_TMPDIR/linked"
out=$(run)
assert_exit "this session's own claim holds nothing" 0 "$?"
git -C "$REPO_DIR" worktree unlock "$TEST_TMPDIR/linked"

run --bad-flag >/dev/null 2>&1
assert_exit "an unknown flag is a usage error" 1 "$?"

[[ $FAILED -eq 0 ]] || exit 1
