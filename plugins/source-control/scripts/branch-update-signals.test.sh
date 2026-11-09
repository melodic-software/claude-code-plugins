#!/usr/bin/env bash
# Regression tests for branch-update-signals.sh and stale-base-overlap.sh, black
# box over a fake gh on PATH and fixture git repositories. Each expected signal
# is written by hand from that signal's rule in branch-update-signals.sh and
# reference/providers/github/branch-update-signals.md. Every run's output is
# also fed to branch-update-method.sh, which must accept it.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGNALS="$SCRIPT_DIR/branch-update-signals.sh"
OVERLAP="$SCRIPT_DIR/stale-base-overlap.sh"
ENGINE="$SCRIPT_DIR/branch-update-method.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
FAKE="$WORKDIR/fake"
SHIM="$WORKDIR/shim"
ROOT="$WORKDIR/gh"
mkdir -p "$FAKE" "$SHIM" "$ROOT/example-org"
export FAKE

# Answers each read the script makes. The JSON shapes are GitHub's published
# REST schemas for a pull request, its commits and reviews, repository rules and
# compare (reference/providers/github/branch-update-signals.md points at each);
# the file each case writes is the only input. FAKE_REFUSE is a regex of calls
# to fail, as a refused read does.
cat >"$SHIM/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE/calls"
if [[ -n ${FAKE_REFUSE:-} && "$*" =~ $FAKE_REFUSE ]]; then
  [[ -z ${FAKE_ERROR_BODY:-} ]] || printf '{"message":"Not Found"}\n'
  echo "refused" >&2
  exit 1
fi
slurp() { [[ -f "$FAKE/$1" ]] && printf '[%s]\n' "$(cat "$FAKE/$1")" || echo '[[]]'; }
case "$*" in
  "repo view --json nameWithOwner"*) echo example-org/app ;;
  "repo view "*) cat "$FAKE/repo" ;;
  "pr list "*) cat "$FAKE/dependents" ;;
  *"/protection/required_status_checks")
    if [[ -f "$FAKE/protection" ]]; then
      printf 'HTTP/2.0 200 OK\r\n\r\n'
      cat "$FAKE/protection"
    else
      printf 'HTTP/2.0 %s\r\n\r\n{"message":"x"}\n' "${FAKE_PROTECTION_STATUS:-404 Not Found}"
      exit 1
    fi
    ;;
  "api -i "*)
    # The file is served by ref: `config` at the base, `config_at_head` at the head.
    args="$*"
    ref="${args##*ref=}"
    ref="${ref%% *}"
    file=""
    [[ "$ref" != "$(jq -r .base.ref "$FAKE/pull")" ]] || file="$FAKE/config"
    [[ "$ref" != "$(jq -r .head.ref "$FAKE/pull")" ]] || file="$FAKE/config_at_head"
    if [[ -n "$file" && -f "$file" ]]; then
      printf 'HTTP/2.0 200 OK\r\nContent-Type: text/plain\r\n\r\n'
      cat "$file"
    else
      printf 'HTTP/2.0 404 Not Found\r\n\r\n{"message":"Not Found"}\n'
      exit 1
    fi
    ;;
  *"/compare/"*) cat "$FAKE/behind" ;;
  *"/pulls/7/commits") slurp commits ;;
  *"/pulls/7/reviews") slurp reviews ;;
  *"/rules/branches/main" | *"/rules/branches/release") slurp base_rules ;;
  *"/rules/branches/"*) slurp head_rules ;;
  "api repos/example-org/"*"/pulls/7") cat "$FAKE/pull" ;;
  *)
    echo "fake gh: unexpected call: $*" >&2
    exit 99
    ;;
esac
EOF
REAL_GIT="$(type -P git)"
cat >"$SHIM/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ \$a == fetch || \$a == ls-remote || \$a == push ]]; then
    exec "$REAL_GIT" -c "url.$ROOT/.insteadOf=https://github.com/" "\$@"
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SHIM/gh" "$SHIM/git"
export PATH="$SHIM:$PATH"

# make_repo <name>: a clone of a fresh bare at github.com/example-org/<name>
# (through the shim), main holding a.txt and b.txt, on feat/x with one commit
# touching a.txt. Sets WC and BARE.
make_repo() {
  BARE="$ROOT/example-org/$1.git"
  WC="$WORKDIR/$1"
  git init -q --bare -b main "$BARE"
  git clone -q "$BARE" "$WC" 2>/dev/null
  git -C "$WC" config user.email alice@example.com
  git -C "$WC" config user.name Alice
  git -C "$WC" checkout -q -b main 2>/dev/null
  printf 'a\n' >"$WC/a.txt"
  printf 'b\n' >"$WC/b.txt"
  git -C "$WC" add -A
  git -C "$WC" commit -q -m init
  git -C "$WC" push -q origin main 2>/dev/null
  git -C "$WC" checkout -q -b feat/x
  printf 'head\n' >>"$WC/a.txt"
  git -C "$WC" commit -q -am head
  git -C "$WC" remote set-url origin "https://github.com/example-org/$1.git"
}

# advance_main <file>: land one commit on the fixture's main, as another PR would.
advance_main() {
  local other="$WC.other"
  [[ -d "$other" ]] || {
    git clone -q -b main "$BARE" "$other" 2>/dev/null
    git -C "$other" config user.email other@example.com
    git -C "$other" config user.name Other
  }
  printf 'base\n' >>"$other/$1"
  git -C "$other" add -A
  git -C "$other" commit -q -m "advance $1"
  git -C "$other" push -q origin main 2>/dev/null
}

# reset_fake <head-sha>: the plain PR 7, one commit by alice, nothing else set.
reset_fake() {
  rm -f "$FAKE"/*
  jq -cn --arg sha "$1" '{
      head: {sha: $sha, ref: "feat/x", repo: {full_name: "example-org/app"}},
      base: {ref: "main", repo: {full_name: "example-org/app"}},
      mergeable: true, mergeable_state: "clean", commits: 1,
      user: {login: "alice", type: "User"}, stack: null
    }' >"$FAKE/pull"
  jq -cn --arg sha "$1" '[{sha: $sha, parents: [{sha: "p"}], author: {login: "alice"}}]' >"$FAKE/commits"
  echo '{"defaultBranchRef":{"name":"main"},"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' >"$FAKE/repo"
  echo 1 >"$FAKE/behind"
  echo 0 >"$FAKE/dependents"
  unset FAKE_REFUSE
}

# patch <file> <jq filter>
patch() {
  local out
  out="$(jq -c "$2" "$FAKE/$1")" && printf '%s\n' "$out" >"$FAKE/$1"
}

# run <dir> <args...>: run the signals script; every run must pass validation.
run() {
  local dir="$1" label="${LABEL:-run}"
  shift
  OUT="$(cd "$dir" && bash "$SIGNALS" "$@" 2>"$WORKDIR/stderr")"
  RC=$?
  ERR="$(cat "$WORKDIR/stderr")"
  DECISION="$(bash "$ENGINE" <<<"$OUT" 2>&1)"
  assert_exit "$label: signals exit" 0 "$RC"
  assert_contains "$label: decision accepted" "$DECISION" '"method":"'
}

sig() { jq -r ".$1" <<<"$OUT" | tr -d '\r'; }
method() { jq -r .method <<<"$DECISION" | tr -d '\r'; }
rule() { jq -r .rule <<<"$DECISION" | tr -d '\r'; }

# expect <label> <signal> <value>: assert one signal of the last run.
expect() { assert_eq "$1" "$3" "$(sig "$2")"; }

# one_signal <label> <signal> <value> [args]: re-run the PR and assert.
one_signal() {
  local label="$1" signal="$2" value="$3"
  shift 3
  LABEL="$label" run "$WC" --pr 7 --repo example-org/app "$@"
  expect "$label" "$signal" "$value"
}

########################################################################
# The overlap helper
########################################################################
make_repo help-disjoint
advance_main b.txt
git -C "$WC" fetch -q origin main 2>/dev/null
assert_eq "overlap, no script, disjoint paths" "no" "$(bash "$OVERLAP" "$WC" origin/main)"

make_repo help-overlap
advance_main a.txt
git -C "$WC" fetch -q origin main 2>/dev/null
assert_eq "overlap, no script, a path changed on both sides" "yes" "$(bash "$OVERLAP" "$WC" origin/main)"

make_repo help-current
assert_eq "overlap, no script, base not moved" "no" "$(bash "$OVERLAP" "$WC" origin/main)"

make_repo help-nobase
assert_contains "overlap, unresolvable ref is unknown" "$(bash "$OVERLAP" "$WC" origin/absent)" "unknown "
assert_contains "overlap, ref starting with - is unknown" "$(bash "$OVERLAP" "$WC" -p)" "unknown "
bash "$OVERLAP" "$WC" >/dev/null 2>&1
assert_exit "overlap, one argument is a usage error" 2 "$?"

# put_rule <repo-side-marker> <exit>: write the overlap rule that records its run.
put_rule() {
  mkdir -p "$1/scripts"
  printf '#!/usr/bin/env bash\ntouch "%s"\nexit %s\n' "$2" "$3" >"$1/scripts/check-stale-base-overlap.sh"
}

# The base's rule runs from a temporary copy; the head's edit and a dirty
# working copy are never run, and the base's verdict is what comes back.
make_repo rule
put_rule "$WC" "$WORKDIR/base-ran" 1
git -C "$WC" add -A
git -C "$WC" commit -q -m "add the rule"
git -C "$WC" push -q origin HEAD:refs/heads/main 2>/dev/null
put_rule "$WC" "$WORKDIR/head-ran" 0
git -C "$WC" add -A
git -C "$WC" commit -q -m "head edits the rule"
put_rule "$WC" "$WORKDIR/wt-ran" 0
advance_main b.txt
git -C "$WC" fetch -q origin main 2>/dev/null
assert_eq "overlap, repo rule exit 1 is an overlap" "yes" "$(bash "$OVERLAP" "$WC" origin/main 2>/dev/null)"
assert_file_exists "overlap, the base's copy ran" "$WORKDIR/base-ran"
assert_file_absent "overlap, the head's copy never ran" "$WORKDIR/head-ran"
assert_file_absent "overlap, the working tree's copy never ran" "$WORKDIR/wt-ran"

# Through the signals script: same fixture, HEAD is the PR head.
SHA="$(git -C "$WC" rev-parse HEAD)"
rm -f "$WORKDIR/base-ran"
reset_fake "$SHA"
one_signal "signals, base rule overlap" base_change_needed yes --repo example-org/rule
assert_file_exists "signals, base rule ran" "$WORKDIR/base-ran"
assert_file_absent "signals, head rule never ran" "$WORKDIR/head-ran"
assert_file_absent "signals, working tree rule never ran" "$WORKDIR/wt-ran"

# With the default branch unread, the base's rule does not run and the paths
# (disjoint here, though the rule says overlap) decide.
rm -f "$WORKDIR/base-ran"
reset_fake "$SHA"
FAKE_REFUSE='^repo view example' one_signal "default branch unread: paths only" base_change_needed no --repo example-org/rule
assert_file_absent "default branch unread: the base rule never ran" "$WORKDIR/base-ran"
assert_eq "overlap --paths-only: disjoint despite the rule" "no" "$(bash "$OVERLAP" --paths-only "$WC" origin/main 2>/dev/null)"
assert_file_absent "overlap --paths-only: the rule never ran" "$WORKDIR/base-ran"
bash "$OVERLAP" --paths-only "$WC" >/dev/null 2>&1
assert_exit "overlap --paths-only, one argument is a usage error" 2 "$?"

# A non-default base holding a rule: never run, overlap still computed.
make_repo rule-nondefault
git -C "$WC" checkout -q -b release main
put_rule "$WC" "$WORKDIR/release-rule-ran" 0
printf 'release\n' >>"$WC/a.txt"
git -C "$WC" add -A
git -C "$WC" commit -q -m release
git -C "$WC" push -q origin release 2>/dev/null
git -C "$WC" checkout -q feat/x
reset_fake "$(git -C "$WC" rev-parse HEAD)"
patch pull '.base.ref = "release"'
one_signal "non-default base with a rule: overlap from the paths" base_change_needed yes --repo example-org/rule-nondefault
assert_file_absent "non-default base with a rule: the rule never ran" "$WORKDIR/release-rule-ran"

########################################################################
# Pull request mode: base_change_needed
########################################################################
make_repo app
advance_main b.txt
git -C "$WC" fetch -q origin main 2>/dev/null
SHA="$(git -C "$WC" rev-parse HEAD)"
reset_fake "$SHA"

one_signal "no overlap, no conflict: base_change_needed no" base_change_needed no
expect "plain PR: head_sha" head_sha "$SHA"
expect "plain PR: behind" behind yes
expect "plain PR: conflict" conflict no
expect "plain PR: native_stack" native_stack no
expect "plain PR: managed_head" managed_head no
expect "plain PR: dependents" dependents no
expect "plain PR: base_merged" base_merged no
expect "plain PR: human_review" human_review no
expect "plain PR: landing" landing squash
expect "plain PR: other_authors" other_authors no
expect "plain PR: rewrite without --allow-rewrite" rewrite blocked
assert_eq "plain PR, behind and disjoint and not required: none" "none" "$(method)"

one_signal "caller says a failure was fixed on the base" base_change_needed yes --base-fixed-failure
patch pull '.mergeable = false'
one_signal "a conflict: base_change_needed yes" base_change_needed yes
expect "a conflict: conflict signal" conflict yes
patch pull '.mergeable = null'
one_signal "mergeable not computed: conflict unknown" conflict unknown
patch pull '.mergeable = true'

reset_fake "$(git -C "$WC" rev-parse main)"
one_signal "checkout is not the PR head: overlap not computed" base_change_needed unknown
expect "checkout is not the PR head: base_merged unknown" base_merged unknown
reset_fake "$SHA"

patch pull '.stack = {number: 3}'
one_signal "stack member behind, no overlap: not no" base_change_needed unknown
echo 0 >"$FAKE/behind"
one_signal "stack member not behind: no" base_change_needed no
expect "stack member: native_stack" native_stack yes
expect "not behind: behind" behind no
reset_fake "$SHA"

make_repo overlapping
advance_main a.txt
git -C "$WC" fetch -q origin main 2>/dev/null
reset_fake "$(git -C "$WC" rev-parse HEAD)"
LABEL="overlap" run "$WC" --pr 7 --repo example-org/overlapping
expect "overlap: base_change_needed yes" base_change_needed yes

# A disjoint fixture for the rest of PR mode.
WC="$WORKDIR/app"
reset_fake "$SHA"

########################################################################
# Pull request mode: rewrite
########################################################################
one_signal "rewrite: pushed head without the flag" rewrite blocked
echo '[{"type":"deletion"}]' >"$FAKE/head_rules"
one_signal "rewrite: --allow-rewrite, no non_fast_forward" rewrite allowed --allow-rewrite
echo '[{"type":"non_fast_forward"}]' >"$FAKE/head_rules"
one_signal "rewrite: --allow-rewrite, non_fast_forward stays blocked" rewrite blocked --allow-rewrite
rm "$FAKE/head_rules"
patch pull '.head.repo.full_name = "fork-owner/app"'
one_signal "rewrite: a fork head is blocked" rewrite blocked --allow-rewrite
patch pull '.head.repo = null'
one_signal "rewrite: a deleted fork head is blocked" rewrite blocked --allow-rewrite
reset_fake "$SHA"
FAKE_REFUSE='rules/branches/feat' one_signal "rewrite: unreadable rules are blocked" rewrite blocked --allow-rewrite
FAKE_ERROR_BODY=1 FAKE_REFUSE='rules/branches/feat' one_signal "rewrite: an error body on stdout is blocked" rewrite blocked --allow-rewrite
reset_fake "$SHA"
echo '"not a list"' >"$FAKE/head_rules"
one_signal "rewrite: a rules answer jq cannot read is blocked" rewrite blocked --allow-rewrite
reset_fake "$SHA"
FAKE_ERROR_BODY=1 FAKE_REFUSE='pulls/7$' one_signal "an error body for the pull request is not a stack answer" native_stack unknown
reset_fake "$SHA"

########################################################################
# Pull request mode: other_authors and human_review
########################################################################
patch commits '.[0].author.login = "ALICE[bot]"'
one_signal "other_authors: case and [bot] suffix normalized" other_authors no
reset_fake "$SHA"
patch commits '. + [{sha: "m", parents: [{sha: "1"}, {sha: "2"}], author: {login: "bob"}}]'
patch pull '.commits = 2'
one_signal "other_authors: a merge commit by another is ignored" other_authors no
reset_fake "$SHA"
patch commits '. + [{sha: "b", parents: [{sha: "1"}], author: {login: "bob"}}]'
patch pull '.commits = 2'
one_signal "other_authors: another author's commit" other_authors yes
reset_fake "$SHA"
patch commits '. + [{sha: "b", parents: [{sha: "1"}], author: null}]'
patch pull '.commits = 2'
one_signal "other_authors: a commit with no account differs" other_authors yes
reset_fake "$SHA"
patch pull '.commits = 300'
one_signal "other_authors: a truncated commit list" other_authors unknown
reset_fake "$SHA"
FAKE_REFUSE='pulls/7/commits' one_signal "other_authors: commits unreadable" other_authors unknown
reset_fake "$SHA"

jq -cn --arg sha "$SHA" '[{user: {login: "reviewer", type: "User"}, state: "APPROVED", commit_id: $sha}]' >"$FAKE/reviews"
one_signal "human_review: a person reviewed a commit on the head" human_review yes
jq -cn --arg sha "$SHA" '[{user: {login: "reviewer", type: "User"}, state: "COMMENTED", commit_id: "gone"}]' >"$FAKE/reviews"
one_signal "human_review: a review of a commit no longer on the head" human_review no
jq -cn --arg sha "$SHA" '[{user: {login: "ci-review", type: "Bot"}, state: "APPROVED", commit_id: $sha}]' >"$FAKE/reviews"
one_signal "human_review: a bot account" human_review no
jq -cn --arg sha "$SHA" '[{user: {login: "ci-review[bot]", type: "User"}, state: "APPROVED", commit_id: $sha}]' >"$FAKE/reviews"
one_signal "human_review: a [bot] login" human_review no
reset_fake "$SHA"
FAKE_REFUSE='pulls/7/reviews' one_signal "human_review: reviews unreadable" human_review unknown
reset_fake "$SHA"

########################################################################
# Pull request mode: landing
########################################################################
echo '[{"type":"merge_queue","parameters":{"merge_method":"MERGE"}}]' >"$FAKE/base_rules"
one_signal "landing: the queue's method wins over squash allowed" landing keeps-commits
echo '[{"type":"merge_queue","parameters":{"merge_method":"SQUASH"}}]' >"$FAKE/base_rules"
one_signal "landing: a squash queue" landing squash
reset_fake "$SHA"
patch repo '.squashMergeAllowed = false | .rebaseMergeAllowed = false'
one_signal "landing: merge the sole method" landing keeps-commits
reset_fake "$SHA"
patch repo '.mergeCommitAllowed = false | .rebaseMergeAllowed = false'
one_signal "landing: squash the sole method" landing squash
reset_fake "$SHA"
patch repo '.rebaseMergeAllowed = false'
one_signal "landing: several allowed, squash among them" landing squash
reset_fake "$SHA"
patch repo '.squashMergeAllowed = false'
one_signal "landing: several allowed, no squash" landing keeps-commits
reset_fake "$SHA"
FAKE_REFUSE='^repo view example' one_signal "landing: repository unreadable" landing unknown
reset_fake "$SHA"
FAKE_REFUSE='rules/branches/main' one_signal "landing: base rules unreadable" landing unknown
reset_fake "$SHA"

########################################################################
# Pull request mode: the remaining signals
########################################################################
for login in "app/dependabot" "dependabot[bot]" "Renovate[bot]" "app/renovate-bot"; do
  patch pull ".user.login = \"$login\""
  one_signal "managed_head: $login" managed_head yes
done
reset_fake "$SHA"

# The dependency-manager list and its normalization are held equal to babysit's.
CLASSIFY_DIR="$SCRIPT_DIR/../skills/babysit-prs/scripts"
PYTHON="$(command -v python3 || command -v python || true)"
if [[ -z "$PYTHON" ]]; then
  fail_discriminating_skip "no python to read babysit_classify.py"
else
  ours="$(sed -n "s/^readonly DEPENDENCY_MANAGERS='\(.*\)'$/\1/p" "$SIGNALS" | tr ' ' '\n' | LC_ALL=C sort | paste -sd' ')"
  theirs="$("$PYTHON" -c 'import sys; sys.path.insert(0, sys.argv[1]); import babysit_classify as b; print(" ".join(sorted(b.DEPENDENCY_MANAGER_LOGINS)))' "$CLASSIFY_DIR" | tr -d '\r')"
  assert_contains "the classifier's set was read" "$theirs" "dependabot"
  assert_eq "managed_head: the same set as babysit_classify.py" "$theirs" "$ours"
  for login in "app/Dependabot[bot]" "APP/Renovate-Bot[BOT]" "dependabot-preview" "app/app/dependabot" "dependabot[bot][bot]" "dependabot-x" "alice"; do
    want="$("$PYTHON" -c 'import sys; sys.path.insert(0, sys.argv[1]); import babysit_classify as b; print("yes" if b.is_dependency_author(sys.argv[2]) else "no")' "$CLASSIFY_DIR" "$login" | tr -d '\r')"
    reset_fake "$SHA"
    patch pull ".user.login = \"$login\""
    one_signal "managed_head normalization agrees with babysit_classify.py: $login" managed_head "$want"
  done
  reset_fake "$SHA"
fi

echo 1 >"$FAKE/dependents"
one_signal "dependents: an open PR based on the head" dependents yes
reset_fake "$SHA"
FAKE_REFUSE='^pr list' one_signal "dependents: unreadable" dependents unknown
reset_fake "$SHA"
echo '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci"}]}}]' >"$FAKE/base_rules"
one_signal "up_to_date_required: a strict rule with a check" up_to_date_required yes
echo '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[]}}]' >"$FAKE/base_rules"
one_signal "up_to_date_required: strict with no checks" up_to_date_required no
rm "$FAKE/base_rules"
one_signal "up_to_date_required: no rules" up_to_date_required no
patch pull '.mergeable_state = "behind"'
one_signal "up_to_date_required: the forge reports behind" up_to_date_required yes
reset_fake "$SHA"
FAKE_REFUSE='rules/branches/main' one_signal "up_to_date_required: unreadable" up_to_date_required unknown
reset_fake "$SHA"

# Classic protection, read when no ruleset says strict.
echo '{"strict":true}' >"$FAKE/protection"
one_signal "up_to_date_required: classic strict" up_to_date_required yes
echo '{"strict":false}' >"$FAKE/protection"
one_signal "up_to_date_required: classic not strict" up_to_date_required no
rm "$FAKE/protection"
one_signal "up_to_date_required: no classic protection (404)" up_to_date_required no
FAKE_PROTECTION_STATUS='403 Forbidden' one_signal "up_to_date_required: classic refused" up_to_date_required unknown
rm -f "$FAKE/calls"
echo '[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"ci"}]}}]' >"$FAKE/base_rules"
FAKE_PROTECTION_STATUS='403 Forbidden' one_signal "up_to_date_required: a strict ruleset answers first" up_to_date_required yes
assert_not_contains "up_to_date_required: a strict ruleset makes no classic call" "$(cat "$FAKE/calls")" "protection/required_status_checks"
reset_fake "$SHA"
echo '{"strict":true}' >"$FAKE/protection"
FAKE_REFUSE='rules/branches/main' one_signal "up_to_date_required: rules unread, classic strict" up_to_date_required yes
reset_fake "$SHA"

# A head that merged the base holds it; a merge of something else does not.
make_repo merged
advance_main b.txt
git -C "$WC" fetch -q origin main 2>/dev/null
git -C "$WC" merge -q --no-edit origin/main
reset_fake "$(git -C "$WC" rev-parse HEAD)"
LABEL="base merged" run "$WC" --pr 7 --repo example-org/merged
expect "base_merged: a merge of the base on the head" base_merged yes
make_repo merged-other
advance_main b.txt
git -C "$WC" branch side
git -C "$WC" checkout -q side
printf 'c\n' >"$WC/c.txt"
git -C "$WC" add -A
git -C "$WC" commit -q -m side
git -C "$WC" checkout -q feat/x
git -C "$WC" merge -q --no-edit side
git -C "$WC" fetch -q origin main 2>/dev/null
reset_fake "$(git -C "$WC" rev-parse HEAD)"
LABEL="other merge" run "$WC" --pr 7 --repo example-org/merged-other
expect "base_merged: a merge of another branch" base_merged no

########################################################################
# Refused reads: every field unknown, nothing fails
########################################################################
WC="$WORKDIR/app"
reset_fake "$SHA"
FAKE_REFUSE='.' LABEL="all refused" run "$WC" --pr 7
for name in behind conflict up_to_date_required base_change_needed native_stack managed_head other_authors dependents base_merged human_review; do
  expect "all refused: $name" "$name" unknown
done
expect "all refused: head_sha is the literal unknown" head_sha unknown
expect "all refused: rewrite is blocked" rewrite blocked
expect "all refused: landing" landing unknown
expect "all refused: setting" setting auto
expect "all refused: setting_level" setting_level default
assert_eq "all refused: unknown stack holds" "hold" "$(method)"

FAKE_REFUSE='.' LABEL="outside a repository" run "$WORKDIR" --branch feat/x --base main
expect "outside a repository: head_sha" head_sha unknown
expect "outside a repository: rewrite is blocked" rewrite blocked

(cd "$WC" && bash "$SIGNALS" >/dev/null 2>&1)
assert_exit "usage: no mode" 2 "$?"
(cd "$WC" && bash "$SIGNALS" --pr abc >/dev/null 2>&1)
assert_exit "usage: --pr not a number" 2 "$?"
(cd "$WC" && bash "$SIGNALS" --pr 7 --branch feat/x >/dev/null 2>&1)
assert_exit "usage: both modes" 2 "$?"
(cd "$WC" && bash "$SIGNALS" --branch feat/x >/dev/null 2>&1)
assert_exit "usage: branch without base" 2 "$?"
(cd "$WC" && bash "$SIGNALS" --pr 7 --repo '-x/y' >/dev/null 2>&1)
assert_exit "usage: repository starting with -" 2 "$?"

########################################################################
# Branch-only mode
########################################################################
branch_run() {
  LABEL="$1" run "$WC" --branch "${BRANCH_NAME:-feat/x}" --base main --repo "example-org/$REPO_NAME" "${@:2}"
}

REPO_NAME=branch-behind
make_repo "$REPO_NAME"
advance_main a.txt
reset_fake "unused"
branch_run "behind no-PR"
expect "branch: behind" behind yes
expect "branch: base_change_needed on overlap" base_change_needed yes
expect "branch: managed_head" managed_head no
expect "branch: native_stack, nothing records it" native_stack no
expect "branch: human_review" human_review no
expect "branch: other_authors, own email" other_authors no
expect "branch: rewrite, never pushed" rewrite allowed
expect "branch: conflict" conflict yes
expect "branch: head_sha" head_sha "$(git -C "$WC" rev-parse feat/x)"
assert_eq "behind no-PR branch: merge, not hold" "merge" "$(method)"
assert_eq "behind no-PR branch: by the squash landing" "squash-landing" "$(rule)"

REPO_NAME=branch-disjoint
make_repo "$REPO_NAME"
advance_main b.txt
reset_fake "unused"
branch_run "behind no-PR, disjoint"
expect "branch, disjoint: base_change_needed" base_change_needed no
expect "branch, disjoint: conflict" conflict no
assert_eq "branch, disjoint and not required: none" "none" "$(method)"

git -C "$WC" -c user.email=bob@example.com commit -q --allow-empty -m bob
branch_run "another email"
expect "branch: another author's email" other_authors yes
git -C "$WC" reset -q --hard HEAD~1
git -C "$WC" -c user.email=ALICE@EXAMPLE.COM commit -q --allow-empty -m me
branch_run "own email, other case"
expect "branch: own email in another case" other_authors no

git -C "$WC" push -q origin feat/x 2>/dev/null
branch_run "pushed branch"
expect "branch: a pushed head without the flag" rewrite blocked
branch_run "pushed, allowed" --allow-rewrite
expect "branch: a pushed head with the flag" rewrite allowed
echo '[{"type":"non_fast_forward"}]' >"$FAKE/head_rules"
branch_run "pushed, rule" --allow-rewrite
expect "branch: non_fast_forward stays blocked" rewrite blocked
rm "$FAKE/head_rules"

# A push remote other than the repository asked about is never rewritten.
mkdir -p "$ROOT/fork-owner"
git init -q --bare -b main "$ROOT/fork-owner/$REPO_NAME.git"
git -C "$WC" remote add fork "https://github.com/fork-owner/$REPO_NAME.git"
git -C "$WC" push -q fork feat/x 2>/dev/null
git -C "$WC" config branch.feat/x.pushRemote fork
branch_run "fork push remote" --allow-rewrite
expect "branch: a pushed branch on a fork remote is blocked" rewrite blocked
git -C "$WC" remote add odd "$WORKDIR/not-github.git"
git -C "$WC" config branch.feat/x.pushRemote odd
branch_run "unparsable push URL"
expect "branch: a push URL that is not github.com is blocked" rewrite blocked
git -C "$WC" config --unset branch.feat/x.pushRemote

STACK_FILE="$(git -C "$WC" rev-parse --absolute-git-dir)/gh-stack"
printf '{"schemaVersion":1,"stacks":[{"trunk":"main","branches":[{"branch":"feat/x"}]}]}' >"$STACK_FILE"
branch_run "stack record"
expect "branch: the gh stack record names it" native_stack yes
printf '{"schemaVersion":1,"stacks":[{"trunk":"main","branches":[{"branch":"other"}]}]}' >"$STACK_FILE"
branch_run "stack record, other"
expect "branch: the record names only other branches" native_stack no
printf 'not json' >"$STACK_FILE"
branch_run "stack record unparsable"
expect "branch: an unparsable record" native_stack unknown
assert_eq "branch: unknown stack holds" "hold" "$(method)"
rm "$STACK_FILE"

echo 2 >"$FAKE/dependents"
branch_run "dependents"
expect "branch: an open PR based on it" dependents yes
echo 0 >"$FAKE/dependents"
git -C "$WC" remote set-url origin https://github.com/example-org/absent.git
branch_run "base unreadable"
expect "branch: base fetch failed: behind" behind unknown
expect "branch: base fetch failed: base_change_needed" base_change_needed unknown
expect "branch: base fetch failed: other_authors" other_authors unknown

########################################################################
# The setting
########################################################################
WC="$WORKDIR/app"
reset_fake "$SHA"
echo 'pr_update_method: rebase' >"$FAKE/config"
LABEL="setting rebase" run "$WC" --pr 7 --repo example-org/app
expect "setting: rebase at the default branch" setting rebase
expect "setting: level" setting_level repository
assert_silent "setting: no notice" "$ERR"

echo 'pr_update_method: fast' >"$FAKE/config"
LABEL="setting unknown" run "$WC" --pr 7 --repo example-org/app
expect "setting: an unknown value is auto" setting auto
expect "setting: not the repository level" setting_level default
assert_contains "setting: unknown value notice" "$ERR" "'fast'"

# Every value the schema allows reaches `setting` and the decision accepts it.
SCHEMA="$SCRIPT_DIR/../schemas/source-control.schema.json"
values="$(jq -r '.properties.pr_update_method.enum[]' "$SCHEMA" | tr -d '\r')"
assert_contains "the schema's values were read" "$values" "rebase"
while IFS= read -r value; do
  echo "pr_update_method: $value" >"$FAKE/config"
  LABEL="schema value $value" run "$WC" --pr 7 --repo example-org/app
  expect "schema value $value reaches setting" setting "$value"
  expect "schema value $value at the repository level" setting_level repository
done <<<"$values"

printf 'pr_update_method:\n  nested: rebase\n' >"$FAKE/config"
LABEL="setting nested" run "$WC" --pr 7 --repo example-org/app
expect "setting: a mapping is not a value" setting auto
assert_contains "setting: nested notice" "$ERR" "pr_update_method"

printf 'pr_update_method: merge\npr_update_method: rebase\n' >"$FAKE/config"
LABEL="setting repeated" run "$WC" --pr 7 --repo example-org/app
expect "setting: a file the parser rejects" setting auto
assert_contains "setting: parse notice" "$ERR" "does not parse"

printf 'pr_update_method: reb\0ase\n' >"$FAKE/config"
LABEL="setting nul" run "$WC" --pr 7 --repo example-org/app
expect "setting: a NUL byte cannot spell a value" setting auto

rm "$FAKE/config"
LABEL="setting absent" run "$WC" --pr 7 --repo example-org/app
expect "setting: no file" setting auto
expect "setting: no file level" setting_level default
assert_silent "setting: no notice without a file" "$ERR"

echo 'pr_update_method: rebase' >"$FAKE/config_at_head"
LABEL="setting served only at the head" run "$WC" --pr 7 --repo example-org/app
expect "setting: a value only the head holds is not read" setting auto
expect "setting: a value only the head holds leaves the default level" setting_level default
rm "$FAKE/config_at_head"

echo 'pr_update_method: rebase' >"$FAKE/config"
FAKE_REFUSE='^api -i' LABEL="setting refused" run "$WC" --pr 7 --repo example-org/app
expect "setting: a refused read is auto" setting auto
assert_contains "setting: refused read notice" "$ERR" "unread"

patch pull '.base.ref = "release"'
LABEL="setting non-default base" run "$WC" --pr 7 --repo example-org/app
expect "setting: non-default base value ignored" setting auto
assert_not_contains "setting: non-default base level" "$(sig setting_level)" "repository"
assert_contains "setting: non-default base notice" "$ERR" "not the default branch"

########################################################################
# PR-supplied text is data
########################################################################
# shellcheck disable=SC2016 # False positive: the literal text is the fixture's branch name.
EVIL='feat/$(touch${IFS}evil-marker)'
reset_fake "$SHA"
patch pull ".head.ref = \"$EVIL\""
one_signal "metacharacters in the head name" dependents no
assert_file_absent "metacharacters: nothing ran" "$WC/evil-marker"
assert_contains "metacharacters: passed as one --base value" "$(grep '^pr list' "$FAKE/calls")" "--base=$EVIL"

reset_fake "$SHA"
patch pull '.head.ref = "-delete"'
one_signal "head name starting with -" dependents no
assert_contains "dash head: an option value, not a flag" "$(grep '^pr list' "$FAKE/calls")" "--base=-delete"

BRANCH_NAME='-x'
REPO_NAME=branch-dash
make_repo "$REPO_NAME"
git -C "$WC" update-ref refs/heads/-x HEAD
reset_fake "unused"
branch_run "branch named -x"
expect "dash branch: head_sha resolved" head_sha "$(git -C "$WC" rev-parse HEAD)"
expect "dash branch: rewrite never pushed" rewrite allowed
unset BRANCH_NAME

printf '\nResults: %d failed of %d\n' "$FAILED" "$CASE_NUM"
[[ $FAILED -eq 0 ]] || exit 1
