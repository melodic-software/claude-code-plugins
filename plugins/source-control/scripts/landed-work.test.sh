#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/landed-work.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

mkfixture() {
  local origin work
  origin="$(mktemp -d "$TEST_TMPDIR/originXXXXXX")"
  work="$(mktemp -d "$TEST_TMPDIR/workXXXXXX")"
  {
    git init -q --bare -b main "$origin"
    git init -q -b main "$work"
    git -C "$work" config user.email t@t.t
    git -C "$work" config user.name t
    git -C "$work" config commit.gpgsign false
    git -C "$work" config core.autocrlf false
    printf 'seed\n' >"$work/README.md"
    git -C "$work" add README.md
    git -C "$work" commit -qm init
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -q -u origin main
    git -C "$work" remote set-head origin main
  } >/dev/null 2>&1
  printf '%s' "$work"
}

commit_in() {
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add "$2" >/dev/null 2>&1
  git -C "$1" commit -qm "$4" >/dev/null 2>&1
}

row() {
  awk -F'\t' -v pat="$2" 'index($1, pat) { print; exit }' <<<"$1"
}

col() {
  awk -F'\t' -v c="$2" '{ print $c; exit }' <<<"$1"
}

C_BRANCH=2
C_UNPUSHED=4
C_LANDED=5
C_METHOD=6
C_INPROGRESS=8
C_CONFLICTED=11
C_PEERS=13
C_RISK=14
C_REASON=15

assert_eq "path-key strips a trailing slash" "$(bash "$ENGINE" --path-key "/a/b/")" "$(bash "$ENGINE" --path-key "/a/b")"
BACKSLASH="$(printf '\134')"
assert_eq "path-key folds backslashes to slashes" \
  "$(bash "$ENGINE" --path-key "/a/b")" "$(bash "$ENGINE" --path-key "${BACKSLASH}a${BACKSLASH}b")"

case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  assert_eq "path-key reconciles the MSYS and Windows drive forms" \
    "$(bash "$ENGINE" --path-key "D:/repos/<repo>")" "$(bash "$ENGINE" --path-key "/d/repos/<repo>")"
  ;;
*)
  assert_eq "path-key leaves a POSIX /d/ path alone off Windows" \
    "/d/repos/x" "$(bash "$ENGINE" --path-key "/d/repos/x")"
  ;;
esac

W="$(mkfixture)"
WT_SQUASH="$TEST_TMPDIR/wt-squash"
git -C "$W" worktree add -q -b feat-squash "$WT_SQUASH" main >/dev/null 2>&1
commit_in "$WT_SQUASH" a.txt "alpha" "add a"
commit_in "$WT_SQUASH" b.txt "beta" "add b"
git -C "$W" merge --squash feat-squash >/dev/null 2>&1
git -C "$W" commit -qm "squash feat-squash" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-squash")"
assert_eq "squash: two commits are unpushed" "2" "$(col "$R" $C_UNPUSHED)"
assert_eq "squash: classified landed" "yes" "$(col "$R" $C_LANDED)"
assert_eq "squash: seen by the range patch-id, which per-commit cannot see" \
  "range-patchid" "$(col "$R" $C_METHOD)"
assert_eq "squash: risk is landed, not stranded" "landed" "$(col "$R" $C_RISK)"

commit_in "$W" a.txt "alpha
gamma" "base advances over a.txt"
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-squash")"
assert_eq "squash: still landed after the base advances" "yes" "$(col "$R" $C_LANDED)"
assert_eq "squash: still by range patch-id after the base advances" \
  "range-patchid" "$(col "$R" $C_METHOD)"

git -C "$W" commit -q --allow-empty -m "empty squash on the base" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-squash")"
assert_eq "squash: still landed past an empty base commit" "yes" "$(col "$R" $C_LANDED)"
assert_not_contains "and the base set is not reported incomplete" \
  "$(col "$R" $C_REASON)" "base-patchid-incomplete"

W="$(mkfixture)"
WT_STRANDED="$TEST_TMPDIR/wt-stranded"
git -C "$W" worktree add -q -b feat-stranded "$WT_STRANDED" main >/dev/null 2>&1
commit_in "$WT_STRANDED" only-here.txt "unique work" "add unique work"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-stranded")"
assert_eq "negative control: not landed" "no" "$(col "$R" $C_LANDED)"
assert_eq "negative control: risk is STRANDED" "STRANDED" "$(col "$R" $C_RISK)"

MERGED_REFS="$TEST_TMPDIR/merged-refs.txt"
printf 'feat-stranded\n' >"$MERGED_REFS"
OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers --merged-refs-file "$MERGED_REFS")"
R="$(row "$OUT" "wt-stranded")"
assert_eq "merged head ref reclassifies landed=no as superseded" \
  "superseded" "$(col "$R" $C_RISK)"

R="$(row "$OUT" "$(basename "$W")")"
assert_eq "nothing unpushed skips the landed computation" "n/a" "$(col "$R" $C_LANDED)"
assert_eq "nothing unpushed is ok" "ok" "$(col "$R" $C_RISK)"

W="$(mkfixture)"
WT_DEL="$TEST_TMPDIR/wt-delete-only"
commit_in "$W" doomed.txt "keep
remove" "base adds doomed.txt"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$W" worktree add -q -b feat-delete-only "$WT_DEL" main >/dev/null 2>&1
commit_in "$WT_DEL" doomed.txt "keep" "branch deletes a line the base still has"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-delete-only")"
assert_eq "a delete-only branch is NOT landed" "no" "$(col "$R" $C_LANDED)"
assert_eq "a delete-only branch is STRANDED" "STRANDED" "$(col "$R" $C_RISK)"

W="$(mkfixture)"
WT_BEHIND="$TEST_TMPDIR/wt-behind"
git -C "$W" worktree add -q -b feat-behind "$WT_BEHIND" main >/dev/null 2>&1
commit_in "$WT_BEHIND" shared.txt "line1
line2" "branch adds shared.txt"
commit_in "$W" shared.txt "line1
line2
line3
line4" "base takes it and adds more"
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-behind")"
assert_eq "merely-behind is not claimed landed without proof" "no" "$(col "$R" $C_LANDED)"
assert_eq "and the method names the test that produced it" "two-dot" "$(col "$R" $C_METHOD)"

W="$(mkfixture)"
WT_WS="$TEST_TMPDIR/wt-whitespace"
commit_in "$W" ws.txt "x" "base seeds ws.txt"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$W" worktree add -q -b feat-whitespace "$WT_WS" main >/dev/null 2>&1
commit_in "$WT_WS" ws.txt "a b" "branch writes spaced content"
commit_in "$W" ws.txt "ab" "base writes unspaced content"
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-whitespace")"
assert_eq "a whitespace-only difference is not landed" "no" "$(col "$R" $C_LANDED)"

W="$(mkfixture)"
WT_PATHS="$TEST_TMPDIR/wt-odd-paths"
git -C "$W" worktree add -q -b feat-odd-paths "$WT_PATHS" main >/dev/null 2>&1
printf 'unique content\n' >"$WT_PATHS/café.txt"
printf 'unique content\n' >"$WT_PATHS/star[1].txt"
git -C "$WT_PATHS" add -A >/dev/null 2>&1
git -C "$WT_PATHS" commit -qm "branch adds oddly-named files" >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-odd-paths")"
assert_eq "a non-ASCII path does not defeat the fallback" "no" "$(col "$R" $C_LANDED)"
assert_eq "and the row is STRANDED, not landed" "STRANDED" "$(col "$R" $C_RISK)"
assert_not_contains "the verdict is not the vacuous empty-match one" \
  "$(col "$R" $C_METHOD)" "two-dot-empty"

W="$(mkfixture)"
WT_EMPTY="$TEST_TMPDIR/wt-empty-commit"
git -C "$W" worktree add -q -b feat-empty "$WT_EMPTY" main >/dev/null 2>&1
commit_in "$WT_EMPTY" e.txt "content" "branch adds content"
git -C "$WT_EMPTY" commit -q --allow-empty -m "marker" >/dev/null 2>&1
git -C "$W" merge --squash feat-empty >/dev/null 2>&1
git -C "$W" commit -qm "squash feat-empty" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-empty-commit")"
assert_eq "an empty commit makes the id set incomplete, so no verdict" "?" "$(col "$R" $C_LANDED)"
assert_contains "and the reason names the incompleteness" \
  "$(col "$R" $C_REASON)" "patchid-set-incomplete"

W="$(mkfixture)"
git -C "$W" checkout -q -b sideA main >/dev/null 2>&1
commit_in "$W" a.txt "a" "A"
git -C "$W" checkout -q -b sideB main >/dev/null 2>&1
commit_in "$W" b.txt "b" "B"
git -C "$W" checkout -q -b crossA sideA >/dev/null 2>&1
git -C "$W" merge -q --no-edit sideB >/dev/null 2>&1
git -C "$W" checkout -q -b crossB sideB >/dev/null 2>&1
git -C "$W" merge -q --no-edit sideA >/dev/null 2>&1
git -C "$W" checkout -q main >/dev/null 2>&1
git -C "$W" branch -f main crossA >/dev/null 2>&1
git -C "$W" push -q -f origin main >/dev/null 2>&1
WT_CROSS="$TEST_TMPDIR/wt-crisscross"
git -C "$W" worktree add -q "$WT_CROSS" crossB >/dev/null 2>&1
commit_in "$WT_CROSS" unique.txt "only here" "branch-only work"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-crisscross")"
if [[ "$(col "$R" $C_LANDED)" == "yes" ]]; then
  fail "a criss-cross history never yields an affirmative verdict" "no or ?" "yes"
else
  pass "a criss-cross history never yields an affirmative verdict"
fi

W="$(mkfixture)"
WT_EOL="$TEST_TMPDIR/wt-eol"
git -C "$W" worktree add -q -b feat-eol "$WT_EOL" main >/dev/null 2>&1
printf 'alpha\nbeta\n' >"$WT_EOL/eol.txt"
git -C "$WT_EOL" add eol.txt >/dev/null 2>&1
git -C "$WT_EOL" commit -qm "branch adds eol.txt with LF" >/dev/null 2>&1
printf 'alpha\r\nbeta\r\n' >"$W/eol.txt"
git -C "$W" add eol.txt >/dev/null 2>&1
git -C "$W" commit -qm "base adds eol.txt with CRLF" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-eol")"
assert_eq "an EOL-only difference is reported unproven, not landed" "no" "$(col "$R" $C_LANDED)"

W="$(mkfixture)"
WT_DETACHED="$TEST_TMPDIR/wt-detached"
git -C "$W" worktree add -q --detach "$WT_DETACHED" main >/dev/null 2>&1
commit_in "$WT_DETACHED" detached-work.txt "no branch holds this" "detached commit"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-detached")"
assert_eq "detached HEAD is reported as such" "(detached)" "$(col "$R" $C_BRANCH)"
assert_eq "detached HEAD reports THIS worktree's own commit" "1" "$(col "$R" $C_UNPUSHED)"
assert_eq "detached HEAD with unlanded work is STRANDED" "STRANDED" "$(col "$R" $C_RISK)"

WT_PEER="$TEST_TMPDIR/wt-peer"
DETACHED_OID="$(git -C "$WT_DETACHED" rev-parse HEAD)"
git -C "$W" worktree add -q --detach "$WT_PEER" "$DETACHED_OID" >/dev/null 2>&1
OUT="$(bash "$ENGINE" --repo-dir "$W")"
R="$(row "$OUT" "wt-detached")"
assert_contains "peer worktree holding the same commits is named" \
  "$(col "$R" $C_PEERS)" "wt-peer"

HUSK="$W/husk-dir"
mkdir -p "$HUSK"
OUT="$(bash "$ENGINE" --worktree "$HUSK" --no-peers)"
R="$(row "$OUT" "husk-dir")"
assert_eq "a directory inside a repo is not a worktree root" "notgit" "$(col "$R" $C_RISK)"
assert_contains "notgit says why the naive probe is wrong" \
  "$(col "$R" $C_REASON)" "not-a-worktree-root"

case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  HUSK_WIN="$(bash "$ENGINE" --path-key "$HUSK")"
  OUT="$(bash "$ENGINE" --worktree "$HUSK_WIN" --no-peers)"
  R="$(row "$OUT" "husk-dir")"
  assert_eq "notgit holds in the Windows drive-form spelling too" \
    "notgit" "$(col "$R" $C_RISK)"
  ;;
*)
  skip_case "Windows-form path pair — single path spelling on this platform"
  ;;
esac

BARE_HUB="$(mktemp -d "$TEST_TMPDIR/hubXXXXXX")/hub.bare"
git init -q --bare -b main "$BARE_HUB" >/dev/null 2>&1
OUT="$(bash "$ENGINE" --repo-dir "$BARE_HUB" --no-peers)"
R="$(row "$OUT" "hub.bare")"
assert_eq "a bare hub is reported as bare, not UNKNOWN" "bare" "$(col "$R" $C_RISK)"
assert_eq "a bare hub has no landed verdict to give" "n/a" "$(col "$R" $C_LANDED)"

OUT="$(bash "$ENGINE" --worktree "$TEST_TMPDIR/does-not-exist" --no-peers)"
R="$(row "$OUT" "does-not-exist")"
assert_eq "an absent path is notgit, never silently omitted" "notgit" "$(col "$R" $C_RISK)"

notgit_head=""
notgit_risk=""
notgit_reason=""
# shellcheck disable=SC2034
while IFS=$'\t' read -r f_path f_branch f_head f_unpushed f_landed f_method f_base \
  f_inprogress f_staged f_unstaged f_conflicted f_untracked f_peers f_risk f_reason; do
  [[ "$f_path" == *does-not-exist* ]] || continue
  notgit_head="$f_head"
  notgit_risk="$f_risk"
  notgit_reason="$f_reason"
done < <(printf '%s\n' "$OUT" | tail -n +2)
assert_eq "a head-less row emits '-', never an empty field" "-" "$notgit_head"
assert_eq "notgit risk lands in the risk column under IFS-tab read" "notgit" "$notgit_risk"
assert_eq "notgit reason lands in the reason column under IFS-tab read" \
  "path-absent" "$notgit_reason"

BARE_HUB2="$(mktemp -d "$TEST_TMPDIR/hub2XXXXXX")/hub2.bare"
git init -q --bare -b main "$BARE_HUB2" >/dev/null 2>&1
OUT="$(bash "$ENGINE" --repo-dir "$BARE_HUB2" --no-peers)"
bare_head=""
bare_risk=""
# shellcheck disable=SC2034  # same full-contract read as the notgit case above.
while IFS=$'\t' read -r f_path f_branch f_head f_unpushed f_landed f_method f_base \
  f_inprogress f_staged f_unstaged f_conflicted f_untracked f_peers f_risk f_reason; do
  [[ "$f_path" == *hub2.bare* ]] || continue
  bare_head="$f_head"
  bare_risk="$f_risk"
done < <(printf '%s\n' "$OUT" | tail -n +2)
assert_eq "a bare hub's head column is '-'" "-" "$bare_head"
assert_eq "bare risk lands in the risk column under IFS-tab read" "bare" "$bare_risk"

NOREMOTE="$(mktemp -d "$TEST_TMPDIR/noremoteXXXXXX")"
git -C "$NOREMOTE" init -q -b main >/dev/null 2>&1
git -C "$NOREMOTE" config user.email t@t.t
git -C "$NOREMOTE" config user.name t
commit_in "$NOREMOTE" seed.txt "seed" "init"
OUT="$(bash "$ENGINE" --repo-dir "$NOREMOTE" --no-peers)"
R="$(row "$OUT" "$(basename "$NOREMOTE")")"
assert_eq "no resolvable base yields ? and never no" "?" "$(col "$R" $C_LANDED)"
assert_eq "no resolvable base is UNKNOWN, which a guard treats as stranded" \
  "UNKNOWN" "$(col "$R" $C_RISK)"
assert_contains "the degradation carries a reason" "$(col "$R" $C_REASON)" "no-base-ref"

W="$(mkfixture)"
WT_MERGE="$TEST_TMPDIR/wt-merge"
git -C "$W" worktree add -q -b feat-merge "$WT_MERGE" main >/dev/null 2>&1
commit_in "$WT_MERGE" conflict.txt "branch side" "branch edits conflict.txt"
commit_in "$W" conflict.txt "base side" "base edits conflict.txt"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$WT_MERGE" merge origin/main >/dev/null 2>&1 || true

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-merge")"
assert_eq "a paused merge is reported as in progress" "merge" "$(col "$R" $C_INPROGRESS)"
assert_eq "the conflicted files are counted apart from the staged tree" \
  "1" "$(col "$R" $C_CONFLICTED)"
assert_contains "the reason says the staged tree is recomputable" \
  "$(col "$R" $C_REASON)" "recomputable"
assert_contains "the reason says the operation's transient state dies with the directory" \
  "$(col "$R" $C_REASON)" "dies with the directory"

(
  LANDED_WORK_LIB=1
  export LANDED_WORK_LIB
  # shellcheck source=/dev/null
  . "$ENGINE"
  assert_row_count 3 3 || exit 1
  assert_row_count 3 2
  rc=$?
  [[ "$rc" -eq 5 ]]
) >/dev/null 2>&1
assert_exit "the row-count assertion fails with exit 5 on a short list" 0 "$?"

TRUNC_ERR="$(
  (
    LANDED_WORK_LIB=1
    export LANDED_WORK_LIB
    # shellcheck source=/dev/null
    . "$ENGINE"
    assert_row_count 3 2
  ) 2>&1 >/dev/null
)"
assert_contains "the short list says how short it was" "$TRUNC_ERR" "enumerated 3"

bash "$ENGINE" --repo-dir "$TEST_TMPDIR" --no-peers >/dev/null 2>&1
assert_exit "a non-repository scope is an environment error" 4 "$?"

bash "$ENGINE" --nonsense >/dev/null 2>&1
assert_exit "an unknown flag is a usage error" 2 "$?"

bash "$ENGINE" --help >/dev/null 2>&1
assert_exit "--help exits 0" 0 "$?"

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
assert_eq "the header names every column" \
  "path	branch	head	unpushed	landed	method	base	inprogress	staged	unstaged	conflicted	untracked	peers	risk	reason" \
  "$(printf '%s' "$OUT" | head -n 1)"

R="$(row "$OUT" "$(basename "$W")")"
unset _p _b _h _u _l _m _base _ip _st _un _cf _ut _pe _risk _reason
IFS=$'\t' read -r _p _b _h _u _l _m _base _ip _st _un _cf _ut _pe _risk _reason <<<"$R"
assert_eq "a tab-splitting consumer lands on the risk column" "ok" "$_risk"
assert_contains "and on the reason column" "$_reason" "nothing-unpushed"
assert_not_contains "no field is empty" "	$R	" "		"

EXPECTED_ROWS="$(git -C "$W" worktree list --porcelain | grep -c '^worktree ')"
ACTUAL_ROWS="$(printf '%s\n' "$OUT" | tail -n +2 | grep -c .)"
assert_eq "one row per registered worktree" "$EXPECTED_ROWS" "$ACTUAL_ROWS"

W="$(mkfixture)"
WT_BISECT="$TEST_TMPDIR/wt-bisect"
git -C "$W" worktree add -q -b feat-bisect "$WT_BISECT" main >/dev/null 2>&1
git -C "$WT_BISECT" bisect start >/dev/null 2>&1
OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-bisect")"
assert_eq "a bisect in progress is probed" "bisect" "$(col "$R" $C_INPROGRESS)"
assert_eq "a bisect in progress is risk=in-progress, never ok" \
  "in-progress" "$(col "$R" $C_RISK)"
git -C "$WT_BISECT" bisect reset >/dev/null 2>&1

W="$(mkfixture)"
WT_OP="$TEST_TMPDIR/wt-inprog-landed"
git -C "$W" worktree add -q -b feat-inprog "$WT_OP" main >/dev/null 2>&1
commit_in "$WT_OP" ip.txt "landed content" "add ip.txt"
commit_in "$W" unrelated.txt "unrelated" "unrelated on main"
git -C "$W" push -q origin main >/dev/null 2>&1
commit_in "$W" ip.txt "landed content" "add ip.txt on main"
git -C "$W" push -q origin main >/dev/null 2>&1
commit_in "$W" extra.txt "extra" "extra on main"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$WT_OP" fetch -q origin >/dev/null 2>&1
git -C "$WT_OP" merge --no-ff --no-commit origin/main >/dev/null 2>&1
OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-inprog-landed")"
assert_eq "fixture sanity: the unpushed commit is landed" "yes" "$(col "$R" $C_LANDED)"
assert_eq "fixture sanity: a merge is mid-flight" "merge" "$(col "$R" $C_INPROGRESS)"
assert_eq "in-progress outranks landed" "in-progress" "$(col "$R" $C_RISK)"

PR_BIN="$TEST_TMPDIR/pr-bin"
mkdir -p "$PR_BIN"
cat >"$PR_BIN/gh" <<'STUB'
#!/usr/bin/env bash
[[ -n "${GH_STUB_LOG:-}" ]] && printf '%s\n' "$*" | tr '\n' ' ' >>"$GH_STUB_LOG" && echo >>"$GH_STUB_LOG"
[[ -n "${GH_STUB_FAIL:-}" ]] && { printf 'gh stub:\tforced; failure\nsecond line\n' >&2; exit 1; }
after='' expr='.'
while (($#)); do
  case "$1" in
  -f) [[ "$2" == after=* ]] && after="${2#after=}"; shift ;;
  --jq) expr="$2"; shift ;;
  esac
  shift
done
[[ -n "$after" && "$after" == "${GH_STUB_FAIL_AFTER:-}" ]] && { echo 'gh stub: page failed' >&2; exit 1; }
f="${GH_STUB_OUT:-/dev/null}${after:+.$after}"
[[ -f "$f" ]] || f=/dev/null
jq -Rn '[inputs | split(" ")] as $l
  | {data: {repository: {pullRequests: {
      pageInfo: {hasNextPage: ($l | any(.[0] == "next")),
        endCursor: ([$l[] | select(.[0] == "next") | .[1]] | first)},
      nodes: (reduce ($l[] | select(.[0] != "next")) as $x ([];
        if $x[0] == "pr" then . + [{headRefName: $x[1], baseRefName: $x[2], commits: {nodes: []}}]
        elif $x[0] == "head" then .[-1].headRefOid = $x[1]
        else .[-1].commits.nodes += [{commit: {oid: $x[1]}}] end))}}}}' "$f" | jq -r "$expr"
STUB
chmod +x "$PR_BIN/gh"

W="$(mkfixture)"
WT_PR="$TEST_TMPDIR/wt-pr"
git -C "$W" worktree add -q -b feat-pr "$WT_PR" main >/dev/null 2>&1
commit_in "$WT_PR" p1.txt "one" "pr commit one"
commit_in "$WT_PR" p2.txt "two" "pr commit two"
PR_C1="$(git -C "$WT_PR" rev-parse HEAD~1)"
PR_C2="$(git -C "$WT_PR" rev-parse HEAD)"
commit_in "$W" other.txt "other" "unrelated on main"
git -C "$W" push -q origin main >/dev/null 2>&1

OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"
R="$(row "$OUT" "wt-pr")"
assert_eq "pr proof: without the flag the row is not landed" "no" "$(col "$R" $C_LANDED)"

run_pr() {
  PATH="$PR_BIN:$PATH" GH_STUB_OUT="$1" GH_STUB_FAIL="${2:-}" \
    bash "$ENGINE" --repo-dir "$W" --no-peers --merged-pr-proof
}

printf 'pr feat-pr main\nhead %s\ncommit %s\ncommit %s\n' "$PR_C2" "$PR_C1" "$PR_C2" >"$TEST_TMPDIR/pr-head-equal"
printf 'pr feat-pr feat-stack-base\nhead %s\ncommit %s\ncommit %s\n' "$PR_C2" "$PR_C1" "$PR_C2" >"$TEST_TMPDIR/pr-stacked"
printf 'pr feat-other main\nhead %s\ncommit %s\ncommit %s\n' "$PR_C2" "$PR_C1" "$PR_C2" >"$TEST_TMPDIR/pr-other-branch"
R="$(row "$(run_pr "$TEST_TMPDIR/pr-head-equal")" "wt-pr")"
assert_eq "pr proof: HEAD equal to the merged PR head is landed" "yes" "$(col "$R" $C_LANDED)"
assert_eq "pr proof: method names the PR head" "merged-pr-head" "$(col "$R" $C_METHOD)"
assert_eq "pr proof: risk is landed" "landed" "$(col "$R" $C_RISK)"
assert_not_contains "pr proof: the reason carries no stale not-landed text" "$(col "$R" $C_REASON)" "head-differs"

R="$(row "$(run_pr "$TEST_TMPDIR/pr-stacked")" "wt-pr")"
assert_eq "pr proof: a PR merged into a non-base branch is not landed" "no" "$(col "$R" $C_LANDED)"

R="$(row "$(run_pr "$TEST_TMPDIR/pr-other-branch")" "wt-pr")"
assert_eq "pr proof: another branch's merged PR is not landed" "no" "$(col "$R" $C_LANDED)"
assert_contains "pr proof: the reason names the missing PR" "$(col "$R" $C_REASON)" "no-merged-pr-into-main-for-branch"
assert_not_contains "pr proof: a short listing is not called full" "$(col "$R" $C_REASON)" "in-newest-"

R="$(row "$(PATH="$PR_BIN:$PATH" GH_STUB_OUT="$TEST_TMPDIR/pr-other-branch" \
  bash "$ENGINE" --repo-dir "$W" --no-peers --merged-pr-proof --merged-pr-limit 1)" "wt-pr")"
assert_contains "pr proof: a full listing says so" "$(col "$R" $C_REASON)" "no-merged-pr-into-main-for-branch-in-newest-1"

printf 'pr feat-pr main\nhead %s\ncommit %s\ncommit %s\n' "0000000000000000000000000000000000000001" "$PR_C1" "$PR_C2" >"$TEST_TMPDIR/pr-commits-only"
R="$(row "$(run_pr "$TEST_TMPDIR/pr-commits-only")" "wt-pr")"
assert_eq "pr proof: every local commit in the PR commit list is landed" "yes" "$(col "$R" $C_LANDED)"
assert_eq "pr proof: method names the commit list" "merged-pr-commits" "$(col "$R" $C_METHOD)"

commit_in "$WT_PR" p3.txt "three" "later commit not in the PR"
R="$(row "$(run_pr "$TEST_TMPDIR/pr-commits-only")" "wt-pr")"
assert_eq "pr proof: a later commit not in the PR is not landed" "no" "$(col "$R" $C_LANDED)"
assert_contains "pr proof: the reason says why" "$(col "$R" $C_REASON)" "local-commits-not-all-in-merged-pr"

R="$(row "$(run_pr "$TEST_TMPDIR/pr-commits-only" 1)" "wt-pr")"
assert_eq "pr proof: a failed read keeps the prior verdict" "no" "$(col "$R" $C_LANDED)"
assert_contains "pr proof: the failed read is named" "$(col "$R" $C_REASON)" "merged-pr-read-failed:gh-pr-list"
assert_contains "pr proof: gh's own error is named" "$(col "$R" $C_REASON)" "gh-pr-list (gh stub: forced  failure)"
assert_not_contains "pr proof: only gh's first error line is kept" "$(col "$R" $C_REASON)" "second line"
assert_eq "pr proof: the error text adds no column" \
  "$(head -n 1 <<<"$OUT" | awk -F'\t' '{print NF}')" "$(awk -F'\t' '{print NF}' <<<"$R")"
OUT="$(bash "$ENGINE" --repo-dir "$W" --no-peers)"

BARE_OUT="$(cd "${ENGINE%/*}" && bash "${ENGINE##*/}" --repo-dir "$W" --no-peers)"
assert_eq "bare-name invocation emits the same rows" "$OUT" "$BARE_OUT"

W="$(mkfixture)"
for n in 1 2 3; do
  git -C "$W" worktree add -q -b "feat-many-$n" "$TEST_TMPDIR/wt-many-$n" main >/dev/null 2>&1
  commit_in "$TEST_TMPDIR/wt-many-$n" "many$n.txt" "many $n" "many $n"
done
commit_in "$W" many-main.txt "main moves" "unrelated on main"
git -C "$W" push -q origin main >/dev/null 2>&1
MANY1="$(git -C "$TEST_TMPDIR/wt-many-1" rev-parse HEAD)"
MANY2="$(git -C "$TEST_TMPDIR/wt-many-2" rev-parse HEAD)"
printf 'pr feat-many-1 main\nhead %s\ncommit %s\npr feat-many-2 main\nhead %s\ncommit %s\n' \
  "$MANY1" "$MANY1" "$MANY2" "$MANY2" >"$TEST_TMPDIR/pr-many"
GH_LOG="$TEST_TMPDIR/gh-calls"
MANY_ERR="$TEST_TMPDIR/many.err"

: >"$GH_LOG"
OUT="$(PATH="$PR_BIN:$PATH" GH_STUB_OUT="$TEST_TMPDIR/pr-many" GH_STUB_LOG="$GH_LOG" \
  bash "$ENGINE" --repo-dir "$W" --no-peers --merged-pr-proof 2>"$MANY_ERR")"
assert_eq "pr listing: three unlanded worktrees make one gh call" "1" "$(grep -c . "$GH_LOG")"
assert_contains "pr listing: the call is one GraphQL query" "$(cat "$GH_LOG")" "api graphql"
assert_contains "pr listing: the query lists merged PRs" "$(cat "$GH_LOG")" "states: MERGED, baseRefName: \$base"
assert_contains "pr listing: the query names the base" "$(cat "$GH_LOG")" "-f base=main"
assert_contains "pr listing: the query reads only commit oids" "$(cat "$GH_LOG")" "commits(first: 100) { nodes { commit { oid } } }"
assert_not_contains "pr listing: the call is not gh pr list --json" "$(cat "$GH_LOG")" "--json"
assert_not_contains "pr listing: the query asks for no commit authors" "$(cat "$GH_LOG")" "authors"
assert_not_contains "pr listing: the call is not scoped to one branch" "$(cat "$GH_LOG")" "headRefName:"
assert_contains "pr listing: the run reports its gh call count" "$(cat "$MANY_ERR")" "merged-pr-proof made 1 gh call(s)"
assert_eq "pr listing: the first branch is proven from the shared listing" \
  "yes" "$(col "$(row "$OUT" "wt-many-1")" $C_LANDED)"
assert_eq "pr listing: the second branch is proven from the shared listing" \
  "yes" "$(col "$(row "$OUT" "wt-many-2")" $C_LANDED)"
assert_eq "pr listing: a branch with no PR in the listing is not landed" \
  "no" "$(col "$(row "$OUT" "wt-many-3")" $C_LANDED)"

: >"$GH_LOG"
OUT="$(PATH="$PR_BIN:$PATH" GH_STUB_OUT="$TEST_TMPDIR/pr-many" GH_STUB_LOG="$GH_LOG" GH_STUB_FAIL=1 \
  bash "$ENGINE" --repo-dir "$W" --no-peers --merged-pr-proof 2>"$MANY_ERR")"
assert_eq "pr listing: a failed listing is read once" "1" "$(grep -c . "$GH_LOG")"
assert_contains "pr listing: a later row still names the failed read" \
  "$(col "$(row "$OUT" "wt-many-3")" $C_REASON)" "merged-pr-read-failed:gh-pr-list"

W2="$(mkfixture)"
git -C "$W2" worktree add -q -b feat-many-1 "$TEST_TMPDIR/wt-other-repo" main >/dev/null 2>&1
commit_in "$TEST_TMPDIR/wt-other-repo" other1.txt "other repo" "other repo commit"
: >"$GH_LOG"
OUT="$(PATH="$PR_BIN:$PATH" GH_STUB_OUT="$TEST_TMPDIR/pr-many" GH_STUB_LOG="$GH_LOG" \
  bash "$ENGINE" --no-peers --merged-pr-proof \
  --worktree "$TEST_TMPDIR/wt-many-1" --worktree "$TEST_TMPDIR/wt-many-2" \
  --worktree "$TEST_TMPDIR/wt-other-repo" 2>"$MANY_ERR")"
assert_eq "pr listing: two repositories make two gh calls" "2" "$(grep -c . "$GH_LOG")"
assert_contains "pr listing: the count covers both repositories" "$(cat "$MANY_ERR")" "merged-pr-proof made 2 gh call(s)"

printf 'next c1\npr feat-many-1 main\nhead %s\ncommit %s\npr feat-gone main\nhead %s\ncommit %s\n' \
  "$MANY1" "$MANY1" "$MANY1" "$MANY1" >"$TEST_TMPDIR/pr-paged"
printf 'pr feat-many-2 main\nhead %s\ncommit %s\n' "$MANY2" "$MANY2" >"$TEST_TMPDIR/pr-paged.c1"
run_paged() {
  : >"$GH_LOG"
  PATH="$PR_BIN:$PATH" GH_STUB_OUT="$TEST_TMPDIR/pr-paged" GH_STUB_LOG="$GH_LOG" \
    bash "$ENGINE" --repo-dir "$W" --no-peers --merged-pr-proof "$@" 2>"$MANY_ERR"
}
OUT="$(run_paged)"
assert_eq "pr paging: two pages make two gh calls" "2" "$(grep -c . "$GH_LOG")"
assert_contains "pr paging: the count names each page" "$(cat "$MANY_ERR")" "merged-pr-proof made 2 gh call(s)"
assert_contains "pr paging: a page holds at most 100 PRs" "$(head -n 1 "$GH_LOG")" "-F first=100"
assert_not_contains "pr paging: the first page has no cursor" "$(head -n 1 "$GH_LOG")" "after="
assert_contains "pr paging: the second page follows the cursor" "$(sed -n 2p "$GH_LOG")" "-f after=c1"
assert_eq "pr paging: a PR on the second page proves its branch" \
  "yes" "$(col "$(row "$OUT" "wt-many-2")" $C_LANDED)"
assert_eq "pr paging: a PR on the first page still proves its branch" \
  "yes" "$(col "$(row "$OUT" "wt-many-1")" $C_LANDED)"

OUT="$(run_paged --merged-pr-limit 1)"
assert_eq "pr paging: a limit the first page fills makes one call" "1" "$(grep -c . "$GH_LOG")"
assert_contains "pr paging: the page asks for no more than the limit" "$(cat "$GH_LOG")" "-F first=1 "
assert_eq "pr paging: a PR past the limit proves nothing" \
  "no" "$(col "$(row "$OUT" "wt-many-2")" $C_LANDED)"

OUT="$(run_paged --merged-pr-limit 3)"
assert_contains "pr paging: the last page asks only for what the limit leaves" "$(sed -n 2p "$GH_LOG")" "-F first=1 "

printf 'next c1\n' >"$TEST_TMPDIR/pr-empty"
printf 'pr feat-many-2 main\nhead %s\ncommit %s\n' "$MANY2" "$MANY2" >"$TEST_TMPDIR/pr-empty.c1"
: >"$GH_LOG"
OUT="$(PATH="$PR_BIN:$PATH" GH_STUB_OUT="$TEST_TMPDIR/pr-empty" GH_STUB_LOG="$GH_LOG" \
  bash "$ENGINE" --repo-dir "$W" --no-peers --merged-pr-proof 2>"$MANY_ERR")"
assert_eq "pr paging: an empty page stops the listing" "1" "$(grep -c . "$GH_LOG")"
assert_eq "pr paging: nothing past an empty page is read" "no" "$(col "$(row "$OUT" "wt-many-2")" $C_LANDED)"

OUT="$(GH_STUB_FAIL_AFTER=c1 run_paged)"
assert_eq "pr paging: a failed page proves nothing" "no" "$(col "$(row "$OUT" "wt-many-1")" $C_LANDED)"
assert_contains "pr paging: the failed page is named" \
  "$(col "$(row "$OUT" "wt-many-1")" $C_REASON)" "merged-pr-read-failed:gh-pr-list (gh stub: page failed)"

for BAD_LIMIT in 0 x; do
  bash "$ENGINE" --repo-dir "$W" --merged-pr-limit "$BAD_LIMIT" >/dev/null 2>&1
  rc=$?
  assert_eq "pr listing: --merged-pr-limit $BAD_LIMIT is a usage error" "2" "$rc"
done

W="$(mkfixture)"
WT_WA="$TEST_TMPDIR/wt-window-a"
WT_WB="$TEST_TMPDIR/wt-window-b"
WT_WC="$TEST_TMPDIR/wt-window-c"
SEED="$(git -C "$W" rev-parse HEAD)"
git -C "$W" worktree add -q -b feat-window-a "$WT_WA" main >/dev/null 2>&1
commit_in "$WT_WA" wa1.txt "window a one" "wa1"
commit_in "$WT_WA" wa2.txt "window a two" "wa2"
git -C "$W" merge --squash feat-window-a >/dev/null 2>&1
git -C "$W" commit -qm "squash feat-window-a" >/dev/null 2>&1
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$W" worktree add -q -b feat-window-b "$WT_WB" main >/dev/null 2>&1
commit_in "$WT_WB" wb1.txt "window b one" "wb1"
commit_in "$WT_WB" wb2.txt "window b two" "wb2"
commit_in "$W" wb1.txt "window b one" "wb1 on main"
commit_in "$W" wb2.txt "window b two" "wb2 on main"
git -C "$W" push -q origin main >/dev/null 2>&1
git -C "$W" worktree add -q -b feat-window-c "$WT_WC" main >/dev/null 2>&1
commit_in "$WT_WC" wc1.txt "window c one" "wc1"
commit_in "$W" wmain.txt "main moves on" "main advances"
git -C "$W" push -q origin main >/dev/null 2>&1

REAL_GIT="$(command -v git)"
SHIM_BIN="$TEST_TMPDIR/git-shim"
WINDOW_LOG="$TEST_TMPDIR/window-renders"
mkdir -p "$SHIM_BIN"
cat >"$SHIM_BIN/git" <<'SHIM'
#!/usr/bin/env bash
case " $* " in
*" --no-walk "*) tee -a "$GIT_SHIM_LOG" | "$REAL_GIT" "$@" ;;
*) exec "$REAL_GIT" "$@" ;;
esac
SHIM
chmod +x "$SHIM_BIN/git"

BASE_TOTAL="$(git -C "$W" rev-list --count --no-merges "$SEED..origin/main")"

for ORDER in newest-first oldest-first; do
  : >"$WINDOW_LOG"
  if [[ "$ORDER" == "newest-first" ]]; then
    TARGETS=(--worktree "$WT_WC" --worktree "$WT_WB" --worktree "$WT_WA")
  else
    TARGETS=(--worktree "$WT_WA" --worktree "$WT_WB" --worktree "$WT_WC")
  fi
  OUT="$(PATH="$SHIM_BIN:$PATH" REAL_GIT="$REAL_GIT" GIT_SHIM_LOG="$WINDOW_LOG" \
    bash "$ENGINE" "${TARGETS[@]}" --no-peers)"
  assert_eq "window ($ORDER): the squash worktree is landed by range patch-id" \
    "range-patchid" "$(col "$(row "$OUT" "wt-window-a")" $C_METHOD)"
  assert_eq "window ($ORDER): the twin-commit worktree is landed per commit" \
    "per-commit-patchid" "$(col "$(row "$OUT" "wt-window-b")" $C_METHOD)"
  assert_eq "window ($ORDER): the unlanded worktree is not landed" \
    "no" "$(col "$(row "$OUT" "wt-window-c")" $C_LANDED)"
  assert_eq "window ($ORDER): every base commit back to the oldest merge-base is hashed" \
    "$BASE_TOTAL" "$(sort -u "$WINDOW_LOG" | grep -c .)"
  assert_eq "window ($ORDER): no base commit is hashed twice across the worktrees" \
    "$BASE_TOTAL" "$(grep -c . "$WINDOW_LOG")"

  for WT in "$WT_WA" "$WT_WB" "$WT_WC"; do
    ALONE="$(bash "$ENGINE" --worktree "$WT" --no-peers | sed -n 2p)"
    assert_eq "window ($ORDER): ${WT##*/} classifies the same alone as beside the others" \
      "$ALONE" "$(row "$OUT" "${WT##*/}")"
  done
done

[[ $FAILED -eq 0 ]] || exit 1
