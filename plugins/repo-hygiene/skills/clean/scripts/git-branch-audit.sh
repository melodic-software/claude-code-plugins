#!/usr/bin/env bash
# shellcheck disable=SC2154
# Branch audit facts for the clean git branch cleanup. No deletion.
#
# Output: PR-map status (PRCount, or PRDataUnavailable; PRDataTruncated when the
# lookup hit its cap); then per branch Branch, Tip, Tier, Age days, PR, Unpushed,
# Loss, Reason (plus Landed, the proof, on a landed branch, and Worktree, the
# checkout path, on a WORKTREE branch); then the LossBlock (LossBlock / LossBranch / LossCommit /
# LossBlockEnd); then TipCapture (or TipCaptureError); Summary line. A missing
# map is NOT the same as a repo with no PRs, and the two are distinguishable
# here on purpose: PR state is what detects a squash merge, so without it a
# landed branch reads as unmerged.
# Exit: 0 (2 on a usage error).
# Omit -e/-o pipefail: script always exits 0 on a successful run; sub-commands
# are best-effort (gh may be absent).
#
# FLEET FORM. --repo / --repos-from select repositories and --skip / --skip-from
# exclude some (the surface clean-batch.sh has, resolved by lib/batch-common.sh).
# Each audited repo is this same script run from inside it, one after another,
# printed as `Repo: <path>` then its unchanged output. A repo whose git common
# dir was already audited (a linked worktree) is reported skipped, and a repo
# that fails is reported without stopping the rest. It deletes no branch and
# moves no ref or working-tree file; what it writes is the tip capture and the
# landed proof's loose objects (below). git-branch-delete.sh is never batched.
#
# LANDED PROOF. A squash or rebase merge leaves a branch that no ancestry check
# can see as merged, and without PR data (no gh, a truncated map) nothing else
# says so. When the chain would end at one of its REVIEW fallbacks (no upstream,
# upstream gone, stale, orphaned) and origin/<default> exists,
# clean_landed_proof (lib/clean-common.sh) looks for the work already on
# origin/<default> in three pure-git steps: `git cherry` finding every commit's
# patch-id there (a rebase or cherry-pick merge; skipped for a branch holding a
# merge commit, which cherry does not list), the branch's tree equal to
# origin/<default>'s (the work landed as differently split commits), or the
# branch's whole diff from its merge-base, re-created as one unreferenced commit,
# finding its patch-id there (a squash merge). Any proof makes the branch
# LIKELY-SAFE, never SAFE, with a `Landed:` line naming the proof, which the
# capture records so git-branch-delete.sh can run the same proof live. It runs
# after the PR MERGED / MERGED_SET / PR CLOSED checks and never touches
# PROTECTED, WORKTREE, a CLOSED PR, or an OPEN PR. Any failed or missing signal
# keeps the verdict, so it can only narrow what an operator must review. A
# landed branch is no longer REVIEW, so the LOSSY tier below never sees it.
# The squash step's `git commit-tree` writes one loose commit object, referenced
# by nothing, for each branch that reaches it; `git gc` prunes it. And each
# `git cherry` patch-ids every commit on origin/<default> since the merge-base,
# so a REVIEW branch costs up to two of them: slow for an old branch in a large
# repository, and a fleet audit multiplies it.
#
# LOSSY TIER. A branch is LOSSY when it is deletable and deleting it loses work:
# it would otherwise be REVIEW, origin/<default> is present so "landed" can be
# evaluated, and `git rev-list <branch> --not --remotes --tags` counts at least
# one commit reachable from no remote-tracking ref and no tag. Those commits
# exist only on this local branch. Other local branches deliberately do NOT
# count as "elsewhere": a sibling in the same deletion batch is not a place the
# work persists. A PR known to be MERGED (a squash changes the SHA, so the count
# would overstate the loss) or OPEN (an active claim on the branch) keeps the
# branch in REVIEW. Every missing or failed signal (no tip, no origin/<default>,
# a failed count) yields `Loss: undetermined` and REVIEW, never LOSSY and never
# SAFE. SAFE and LIKELY-SAFE are decided before this step (the landed proof
# above included); LOSSY is carved out of REVIEW only, so this tier can widen
# what an operator must confirm and can never narrow it.
#
# BULK READS. Git is asked about the branches together, not one at a time: one
# for-each-ref carries every branch's tip, upstream and ahead/behind summary, and
# one ancestry pass each gives the commits absent from origin/<default> and the
# LOSSY count above, the numbers `git rev-list --count` prints per branch. The
# git calls outside the LossCommit listings therefore do not grow with the branch
# count. What stays per branch: the LossCommit listing (one `git log` per LOSSY
# branch, since a shared walk can order commits differently when dates tie or
# skew), and any branch whose bulk record cannot be trusted (a short name
# ambiguous with a tag or a remote, a `[gone]` upstream whose ref exists, an
# unrecognized ahead/behind summary), which takes the per-branch commands. A pass
# that fails is answered the same way, so a verdict never depends on which path
# answered.
#
# The LOSSY set is printed again as its own block after the per-branch records,
# one LossBranch line per branch with the commits that would be lost, so the
# operator confronts it as a separate decision before any deletion is
# confirmed: a prose flag beside a verdict column is easy to skim past.
#
# MAIN CHECKOUT. Before the branch records, `MainCheckout:` names what the audit
# runs from: the branch or `detached at <short sha>`, then `MainCheckoutDirty:`
# (the `git status --porcelain` line count) and one `MainCheckoutOperation:
# <name> <path>` per in-progress operation (MERGE_HEAD, rebase-merge,
# rebase-apply, CHERRY_PICK_HEAD, REVERT_HEAD, BISECT_LOG). An operation in
# progress means the checkout is mid-change, so no branch is offered as deletable:
# SAFE, LIKELY-SAFE and LOSSY become REVIEW with the reason `operation in
# progress: <path>`, and `OperationInProgress: <path>` is printed. Detached and
# dirty state are reported and do not block.
#
# TIP CAPTURE. Every branch's tip commit is written, together with its verdict,
# upstream and ahead/behind counts, to a durable TSV under the repository's
# common git dir (`.git/repo-hygiene/branch-tips/<utc-stamp>-<pid>.tsv`), and
# the path is printed as `TipCapture: <path>`. That file is the precondition
# git-branch-delete.sh demands before it deletes anything: a deleted branch is
# restorable only from its tip, and the tip must be recorded BEFORE the delete,
# not remembered from a transcript. The capture is written to a `.part` file
# (created exclusively, so two runs can never share one) and renamed into place
# only when every row landed; any failure (no writable location, a short write)
# yields `TipCaptureError:` instead of a path, so a partial capture can never
# present itself as a complete one. Rows are recognized by shape (ten
# tab-separated columns, a commit id in the second), never by a leading `#`,
# which is a legal first character of a branch name.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"
# shellcheck source=lib/batch-common.sh
source "$SCRIPT_DIR/lib/batch-common.sh"

usage() {
  cat <<'EOF'
git-branch-audit.sh - emit branch audit facts for the clean git tier.

Usage:
  git-branch-audit.sh [--capture-file PATH]
  git-branch-audit.sh [--repo DIR...]... [--repos-from FILE|-]...
                      [--skip ENTRY]... [--skip-from FILE]... [--capture-file PATH]
  git-branch-audit.sh --help

  --capture-file PATH  write the branch-tip capture to PATH instead of the
                       default <git-common-dir>/repo-hygiene/branch-tips/<utc-stamp>-<pid>.tsv
  --repo DIR...        audit these repositories instead of the current one
                       (repeatable; takes every consecutive non-flag path, so a
                       shell glob works)
  --repos-from FILE    newline-delimited repo paths (FILE, or - for stdin)
  --skip ENTRY         skip a repo: absolute path, owner/repo, or repo (repeatable)
  --skip-from FILE     newline-delimited skip entries

With --repo / --repos-from the repositories are audited one after another. Each
block is `Repo: <path>`, the output described below, then `---`. A repo sharing a
git common dir with an audited one (a linked worktree) is reported `Outcome:
skipped`; a skip-listed, unresolvable, or failing repo is reported without
stopping the rest; `FleetSummary: repos=N audited=A skipped=S duplicate=D
blocked=B failed=F` closes the run (exit 0). Each repo writes its own default
capture and prints its own `TipCapture:`; --capture-file with more than one repo
is a usage error (exit 2). Deletion is never batched: run git-branch-delete.sh
from inside the audited repo with that repo's capture.

Leading: PRCount or PRDataUnavailable, optional PRDataTruncated. Then
`MainCheckout: <branch | detached at <sha>>`, `MainCheckoutDirty: <n>` and a
`MainCheckoutOperation: <name> <path>` per merge, rebase, cherry-pick, revert or
bisect in progress; any of those prints `OperationInProgress: <path>` and demotes
SAFE, LIKELY-SAFE and LOSSY to REVIEW.
Per branch: Branch, Tip, Tier, Age days, PR, Unpushed, Loss, Reason; a landed
branch adds `Landed: <proof>`; a WORKTREE branch adds `Worktree: <path>`, the worktree that has it checked out.
Tiers: PROTECTED, WORKTREE, SAFE, LIKELY-SAFE, LOSSY, REVIEW. A branch whose work
origin/<default> already holds, by patch-id (`git cherry`), by tree equality, or
as one squashed diff, is LIKELY-SAFE with a `Landed:` line, unless its PR is OPEN
or CLOSED. The squash check writes one unreferenced loose commit object per
branch that reaches it (`git gc` prunes it).
LOSSY is a branch that is deletable but whose deletion loses commits present on
no remote ref and no tag; its `Loss:` line carries the count. A loss that cannot be determined is
`Loss: undetermined (<why>)` and the branch stays REVIEW.
Then the loss block, `LossBlock: <n> ...` to `LossBlockEnd: <n>`, listing every
LOSSY branch (LossBranch) and the commits it would lose (LossCommit, at most
CLEAN_LOSS_COMMITS_SHOWN per branch, default 10). Surface it as its own decision
before any deletion is confirmed; git-branch-delete.sh admits LOSSY only under
--accept-loss.
Then `TipCapture: <path>` (the durable tip record git-branch-delete.sh requires)
or `TipCaptureError: <why>` when it could not be written completely.
Restore a branch from a captured tip: git branch <branch> <tip>

Does NOT delete branches. Exit: 0 (2 on a usage error).
EOF
}

CAPTURE_ARG=""
FLEET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --capture-file)
    if [[ -z "${2:-}" ]]; then
      echo "git-branch-audit.sh: --capture-file requires a value" >&2
      exit 2
    fi
    CAPTURE_ARG="$2"
    shift 2
    ;;
  --repo | --repos-from | --skip | --skip-from)
    if ! batch_take_selection_arg "$@"; then
      echo "git-branch-audit.sh: $BATCH_ARG_ERROR" >&2
      exit 2
    fi
    [[ "$1" == --skip* ]] || FLEET=1
    shift "$BATCH_ARG_SHIFT"
    ;;
  *)
    echo "git-branch-audit.sh: unknown arg '$1'" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [[ $FLEET -eq 0 && ${#BATCH_SKIP_INPUTS[@]} -gt 0 ]]; then
  echo "git-branch-audit.sh: --skip / --skip-from need --repo or --repos-from" >&2
  exit 2
fi
if [[ $FLEET -eq 1 ]]; then
  if [[ ${#BATCH_REPO_INPUTS[@]} -eq 0 ]]; then
    echo "git-branch-audit.sh: no repos given (use --repo and/or --repos-from)" >&2
    exit 2
  fi
  batch_resolve_repos "${BATCH_REPO_INPUTS[@]}"
  if [[ -n "$CAPTURE_ARG" && ${#BATCH_TOPS[@]} -gt 1 ]]; then
    echo "git-branch-audit.sh: --capture-file names one file and cannot serve ${#BATCH_TOPS[@]} repos; omit it so each repo writes its own default capture" >&2
    exit 2
  fi
  child_args=()
  [[ -n "$CAPTURE_ARG" ]] && child_args=(--capture-file "$CAPTURE_ARG")
  batch_run_fleet "$SCRIPT_DIR/git-branch-audit.sh" ${child_args[@]+"${child_args[@]}"}
  exit 0
fi

REPO_ROOT="$(clean_repo_root)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not a git repository"
  exit 0
fi

DEFAULT_BRANCH="$(clean_default_branch "$REPO_ROOT")"

CURRENT_BRANCH="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null | tr -d '\r')"

# Tip capture setup. The capture is opened before the first branch is classified
# and every row is appended as its branch is reported, so the file mirrors the
# output exactly. CAPTURE_ERROR, once set, is sticky: nothing after it can turn a
# failed capture back into a reported path.
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMON_DIR="$(clean_git_common_dir "$REPO_ROOT")" || COMMON_DIR=""
CAPTURE_ERROR=""
CAPTURE_ROWS=0
if [[ -n "$CAPTURE_ARG" ]]; then
  CAPTURE_PATH="$CAPTURE_ARG"
elif [[ -n "$COMMON_DIR" ]]; then
  CAPTURE_PATH="$COMMON_DIR/repo-hygiene/branch-tips/$(date -u +%Y%m%dT%H%M%SZ)-$$.tsv"
else
  CAPTURE_PATH=""
  CAPTURE_ERROR="cannot resolve the git common dir for a default capture location; pass --capture-file PATH"
fi
CAPTURE_TMP="${CAPTURE_PATH}.part"
CAPTURE_TMP_OWNED=0
if [[ -z "$CAPTURE_ERROR" ]]; then
  # noclobber makes the create exclusive: a `.part` left by another run (a
  # <stamp>-<pid> collision across PID namespaces sharing the mount, or an
  # interrupted audit) is refused rather than appended to, so two runs can
  # never interleave rows into one file. The other run's file is left alone.
  if ! mkdir -p "$(dirname "$CAPTURE_PATH")" 2>/dev/null; then
    CAPTURE_ERROR="cannot create $(dirname "$CAPTURE_PATH")"
  elif ! (set -C && : >"$CAPTURE_TMP") 2>/dev/null; then
    if [[ -e "$CAPTURE_TMP" ]]; then
      CAPTURE_ERROR="refusing to reuse existing $CAPTURE_TMP (another audit is writing it, or one was interrupted); remove it or pass --capture-file PATH"
    else
      CAPTURE_ERROR="cannot write $CAPTURE_TMP"
    fi
  else
    CAPTURE_TMP_OWNED=1
  fi
fi

capture_line() {
  [[ -n "$CAPTURE_ERROR" ]] && return 0
  if ! printf '%s\n' "$1" >>"$CAPTURE_TMP" 2>/dev/null; then
    CAPTURE_ERROR="write failed: $CAPTURE_TMP"
  fi
}

capture_line "# repo-hygiene branch tip capture v1"
capture_line "# repo: $REPO_ROOT"
capture_line "# common_dir: ${COMMON_DIR:-unknown}"
capture_line "# default_branch: $DEFAULT_BRANCH"
capture_line "# captured_at: $CAPTURED_AT"
capture_line "# restore: git branch <branch> <tip>"
capture_line $'# columns: branch\ttip\ttier\tpr\tupstream\tahead\tbehind\tnot_on_default\tlanded\tcaptured_at'

# PR map: branch → state, the mitigation for squash merges that `git --merged`
# cannot see. clean_pr_map emits PRCount / PRDataTruncated / PRDataUnavailable
# onto this script's stdout, so a short or missing map is visible to the reader
# instead of silently degrading every SAFE/REVIEW verdict below.
declare -A PR_STATE=()
declare -A PR_NUM=()
declare -A PR_REFOID=()
PR_MAP_FILE="$(mktemp 2>/dev/null)" || PR_MAP_FILE="${TMPDIR:-/tmp}/clean-pr-map.$$"
trap 'rm -f "$PR_MAP_FILE"' EXIT
clean_pr_map "$PR_MAP_FILE" 'headRefName,state,number,headRefOid'
if [[ -f "$PR_MAP_FILE" ]]; then
  while IFS=$'\t' read -r head state num refoid; do
    [[ -z "$head" ]] && continue
    PR_STATE["$head"]="$state"
    PR_NUM["$head"]="$num"
    PR_REFOID["$head"]="$refoid"
  done <"$PR_MAP_FILE"
fi

# The checkout the audit runs from: HEAD, dirty count, in-progress operations.
MAIN_HEAD_LINE="$CURRENT_BRANCH"
[[ -n "$MAIN_HEAD_LINE" ]] || MAIN_HEAD_LINE="detached at $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null | tr -d '\r')"
printf 'MainCheckout: %s\n' "$MAIN_HEAD_LINE"
printf 'MainCheckoutDirty: %s\n' "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' \r')"
OP_PATH=""
for op_name in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
  op_file="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path "$op_name" 2>/dev/null | tr -d '\r')"
  if [[ -n "$op_file" && -e "$op_file" ]]; then
    printf 'MainCheckoutOperation: %s %s\n' "$op_name" "$op_file"
    OP_PATH="${OP_PATH:-$op_file}"
  fi
done
[[ -n "$OP_PATH" ]] && printf 'OperationInProgress: %s\n' "$OP_PATH"

# Membership sets, each read once. WORKTREE_PATH maps a branch to the worktree
# that has it checked out.
declare -A WORKTREE_PATH=() GONE_SET=() MERGED_SET=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  WORKTREE_PATH["${line%%$'\t'*}"]="${line#*$'\t'}"
done < <(clean_worktree_branch_paths "$REPO_ROOT")
GONE_BRANCHES="$(git -C "$REPO_ROOT" branch -vv 2>/dev/null | grep ': gone]' | awk '{print $1}' | tr -d '\r')"
MERGED_BRANCHES="$(git -C "$REPO_ROOT" branch --merged "origin/${DEFAULT_BRANCH}" 2>/dev/null | sed 's/^[ *]*//' | grep -v "^${DEFAULT_BRANCH}$" | tr -d '\r' || true)"
while IFS= read -r line; do
  [[ -n "$line" ]] && GONE_SET["$line"]=1
done <<<"$GONE_BRANCHES"
while IFS= read -r line; do
  [[ -n "$line" ]] && MERGED_SET["$line"]=1
done <<<"$MERGED_BRANCHES"

# Bulk reads. One for-each-ref record per local branch carries the tip, the
# upstream and its ahead/behind summary, so nothing below asks git about a branch
# one at a time. The two counts a verdict needs that for-each-ref cannot give,
# commits absent from origin/<default> and the LOSSY loss count, come from one
# ancestry pass each (clean_unreached_counts). A branch whose record cannot be
# trusted (see bulk_facts), or a pass that fails, falls back to the per-branch
# commands, so a verdict never depends on which path answered.
ORIGIN_DEFAULT=0
if git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/${DEFAULT_BRANCH}" >/dev/null 2>&1; then
  ORIGIN_DEFAULT=1
fi
REC_SEP=$'\x1f'
mapfile -t REF_RECORDS < <(git -C "$REPO_ROOT" for-each-ref refs/heads/ \
  --format='%(refname)%1f%(refname:short)%1f%(objectname)%1f%(objecttype)%1f%(committerdate:unix)%1f%(upstream)%1f%(upstream:short)%1f%(upstream:track)' 2>/dev/null | tr -d '\r')

# The tips a branch's record can vouch for: its ref is refs/heads/<short name>
# (a branch named like a tag has a short name that is not) and it is a commit.
bulk_record_ok() { # <refname> <short name> <object type>
  [[ "$1" == "refs/heads/$2" && "$3" == commit ]]
}

declare -A COUNT=()
# load_counts <key> <rev>...: COUNT[<key>:<tip>] for every bulk tip; nothing
# when the pass fails.
load_counts() {
  local key="$1" out oid n
  shift
  out="$(printf '%s' "$BULK_TIPS" | clean_unreached_counts "$REPO_ROOT" "$@")" || return 0
  while read -r oid n; do
    [[ -n "$oid" ]] && COUNT["$key:$oid"]="$n"
  done <<<"$out"
}
BULK_TIPS="" GONE_UPSTREAMS=""
for line in ${REF_RECORDS[@]+"${REF_RECORDS[@]}"}; do
  IFS=$REC_SEP read -r refname branch tip otype _ upfull _ track <<<"$line"
  bulk_record_ok "$refname" "$branch" "$otype" || continue
  BULK_TIPS+="$tip"$'\n'
  [[ -n "$upfull" && "$track" == "[gone]" ]] && GONE_UPSTREAMS+="$upfull"$'\n'
done
if [[ $ORIGIN_DEFAULT -eq 1 ]]; then
  load_counts ahead "origin/${DEFAULT_BRANCH}"
  load_counts loss --remotes --tags
fi

# `[gone]` means the upstream ref is missing, which is what makes rev-parse read
# the branch as having no upstream. An upstream ref that exists but does not
# point at a commit prints `[gone]` too, and rev-parse reads that as an upstream,
# so those branches take the per-branch commands. One cat-file answers for every
# gone branch; if it fails, every one of them takes the per-branch commands.
declare -A UPSTREAM_EXISTS=()
if [[ -n "$GONE_UPSTREAMS" ]]; then
  mapfile -t GONE_NAMES <<<"${GONE_UPSTREAMS%$'\n'}"
  mapfile -t GONE_ANSWERS < <(printf '%s' "$GONE_UPSTREAMS" | git -C "$REPO_ROOT" cat-file --batch-check 2>/dev/null | tr -d '\r')
  for i in "${!GONE_NAMES[@]}"; do
    [[ "${GONE_ANSWERS[$i]:-}" == *" missing" ]] || UPSTREAM_EXISTS["${GONE_NAMES[$i]}"]=1
  done
fi

prot=0 wt=0 safe=0 likely=0 lossy=0 review=0
NOW=$(date +%s)

# The LOSSY set, collected during classification and printed as its own block
# after the per-branch records. Parallel arrays indexed by position.
LOSSY_BRANCHES=()
LOSSY_COUNTS=()
LOSSY_REASONS=()
LOSSY_TIPS=()
LOSS_COMMITS_SHOWN="${CLEAN_LOSS_COMMITS_SHOWN:-10}"
[[ "$LOSS_COMMITS_SHOWN" =~ ^[0-9]+$ ]] || LOSS_COMMITS_SHOWN=10

# bulk_facts: read local_tip, upstream, ahead_up and behind_up from the branch's
# for-each-ref record (the caller's refname, tip, otype, upfull, upshort and
# track). Returns 1 when the record is not one the per-branch commands would
# read the same way, and the caller then runs them: a ref whose short name is
# ambiguous (see bulk_record_ok), a `[gone]` upstream whose ref exists (see
# UPSTREAM_EXISTS), or an ahead/behind summary in a form other than the ones git
# documents. An upstream whose tracking ref is missing prints `[gone]`, which is
# `rev-parse --abbrev-ref <branch>@{upstream}` failing: no upstream. An upstream
# that is level with the branch prints nothing, which is 0 ahead and 0 behind.
bulk_facts() {
  bulk_record_ok "$refname" "$branch" "$otype" || return 1
  local up="" a="" b=""
  if [[ -n "$upfull" && "$track" == "[gone]" ]]; then
    [[ -z "${UPSTREAM_EXISTS[$upfull]+x}" ]] || return 1
  elif [[ -n "$upfull" ]]; then
    up="$upshort" a=0 b=0
    if [[ -z "$track" ]]; then
      :
    elif [[ "$track" =~ ^\[ahead\ ([0-9]+)\]$ ]]; then
      a="${BASH_REMATCH[1]}"
    elif [[ "$track" =~ ^\[behind\ ([0-9]+)\]$ ]]; then
      b="${BASH_REMATCH[1]}"
    elif [[ "$track" =~ ^\[ahead\ ([0-9]+),\ behind\ ([0-9]+)\]$ ]]; then
      a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[2]}"
    else
      return 1
    fi
  fi
  local_tip="$tip" upstream="$up" ahead_up="$a" behind_up="$b"
}

# branch_loss_count: set lost to the caller's branch loss count (commits on no
# remote ref and no tag): from the bulk pass when it answered for this branch's
# tip, else from clean_loss_count. Status 1 when neither could count.
branch_loss_count() {
  if [[ $bulk -eq 1 && -n "${COUNT["loss:$local_tip"]+x}" ]]; then
    lost="${COUNT["loss:$local_tip"]}"
  else
    lost="$(clean_loss_count "$REPO_ROOT" "$branch")"
  fi
}

classify_branch() {
  local branch="$1" age_days="$2" refname="$3" tip="$4" otype="$5" upfull="$6" upshort="$7" track="$8"
  local tier reason pr_line="none" local_tip bulk=0
  local upstream no_upstream=0 ahead_default="" unpushed_line ahead_up="" behind_up=""
  local loss_line lost="" row landed_reason=""

  # The tip is the one fact that makes a deleted branch restorable, so it is
  # resolved first and reported for every branch regardless of verdict: a
  # verdict can be wrong in either direction, and the tip is what recovers from
  # that. An unresolvable tip is reported as such and gets no capture row, which
  # makes the branch undeletable through git-branch-delete.sh.
  #
  # No-upstream branches are invisible to `@{upstream}`-based ahead/behind
  # reporting (it yields nothing), so never-pushed local work goes unseen. Detect
  # the missing upstream and, when origin/<default> exists, count the branch's
  # commits absent from it — surfaced below as its own class and Unpushed line.
  # `rev-parse --abbrev-ref` echoes its input to stdout on failure (no upstream
  # configured, or a configured upstream whose tracking ref is unfetched), so gate
  # on its exit status rather than on empty output — otherwise that echo reads as a
  # real upstream.
  if bulk_facts; then
    bulk=1
  else
    local_tip="$(git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$branch" 2>/dev/null | tr -d '\r')"
    if upstream="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref "${branch}@{upstream}" 2>/dev/null)"; then
      upstream="${upstream%$'\r'}"
    else
      upstream=""
    fi
  fi
  [[ -z "$upstream" ]] && no_upstream=1
  # Commits on this branch absent from origin/<default> — the work lost if the
  # branch were deleted. Computed for every branch (when origin/<default> exists)
  # so both the upstream-gone and no-upstream classes can guard deletion on it: a
  # `gone` upstream normally means merged-and-deleted, but a gone branch still
  # carrying such commits is unmerged local work, not a safe-delete candidate.
  if [[ $ORIGIN_DEFAULT -eq 1 ]]; then
    if [[ $bulk -eq 1 && -n "${COUNT["ahead:$local_tip"]+x}" ]]; then
      ahead_default="${COUNT["ahead:$local_tip"]}"
    else
      ahead_default="$(git -C "$REPO_ROOT" rev-list --count "origin/${DEFAULT_BRANCH}..refs/heads/${branch}" 2>/dev/null | tr -d '\r')"
    fi
  fi

  if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
    tier="PROTECTED"
    reason="current branch"
  elif [[ "$branch" == "$DEFAULT_BRANCH" ]]; then
    tier="PROTECTED"
    reason="default branch"
  elif clean_branch_matches_protected_pattern "$branch"; then
    tier="PROTECTED"
    reason="protected pattern"
  elif [[ -n "${WORKTREE_PATH[$branch]+x}" ]]; then
    tier="WORKTREE"
    reason="checked out in worktree — clean up the worktree first"
  elif [[ "${PR_STATE[$branch]:-}" == "MERGED" ]]; then
    if [[ -n "${PR_REFOID[$branch]:-}" && -n "$local_tip" && "$local_tip" != "${PR_REFOID[$branch]}" ]]; then
      tier="REVIEW"
      reason="PR merged but branch has commits since merge"
      pr_line="#${PR_NUM[$branch]} MERGED (tip drift)"
    else
      tier="SAFE"
      reason="PR merged"
      pr_line="#${PR_NUM[$branch]} MERGED"
    fi
  elif [[ -n "${MERGED_SET[$branch]+x}" ]]; then
    tier="SAFE"
    reason="merged (git ancestry)"
  elif [[ "${PR_STATE[$branch]:-}" == "CLOSED" ]]; then
    tier="REVIEW"
    reason="PR closed without merge"
    pr_line="#${PR_NUM[$branch]} CLOSED"
  elif [[ -n "${GONE_SET[$branch]+x}" ]]; then
    if [[ -z "$ahead_default" ]]; then
      # Upstream gone AND no origin/<default> to compare against (feature-only
      # clone, unfetched/missing remote HEAD): the script cannot prove the branch
      # is merged, so fail closed to REVIEW rather than offer it as a deletable
      # LIKELY-SAFE candidate that might carry local-only commits.
      tier="REVIEW"
      reason="upstream gone, cannot compare against origin/${DEFAULT_BRANCH}"
    elif [[ "$ahead_default" -gt 0 ]]; then
      tier="REVIEW"
      reason="upstream gone, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
    else
      tier="LIKELY-SAFE"
      reason="upstream gone"
    fi
  elif [[ "$no_upstream" == 1 && -n "$ahead_default" && "$ahead_default" -gt 0 ]]; then
    tier="REVIEW"
    reason="no upstream, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
  elif [[ "$age_days" -gt "$CLEAN_STALE_BRANCH_DAYS" ]]; then
    tier="REVIEW"
    reason="stale (${age_days}d)"
  else
    tier="REVIEW"
    reason="orphaned or needs review"
  fi

  # Landed proof, only for a branch the chain left in one of its REVIEW
  # fallbacks: the PR-state REVIEW verdicts (CLOSED, merged with tip drift) and
  # an OPEN PR are claims about the branch that a patch-id match does not
  # answer.
  if [[ "$tier" == REVIEW && $ORIGIN_DEFAULT -eq 1 && -n "$local_tip" && -n "$ahead_default" ]]; then
    case "${PR_STATE[$branch]:-}" in
    MERGED | CLOSED | OPEN) ;;
    *)
      if landed_reason="$(clean_landed_proof "$REPO_ROOT" "$DEFAULT_BRANCH" "$branch")"; then
        tier="LIKELY-SAFE"
        reason="$landed_reason"
      fi
      ;;
    esac
  fi

  # An operation in progress in the checkout offers no deletable tier, so a
  # landed proof no longer describes the verdict.
  if [[ -n "$OP_PATH" && ("$tier" == SAFE || "$tier" == LIKELY-SAFE) ]]; then
    tier="REVIEW"
    reason="operation in progress: $OP_PATH"
    landed_reason=""
  fi

  # Loss assessment, and the REVIEW -> LOSSY refinement. Only a REVIEW verdict
  # is ever refined, and only upward into "deletable, loses work": every branch
  # the chain above already deemed safe keeps its verdict untouched, and every
  # signal that is missing or failed leaves the branch in REVIEW with the reason
  # spelled out. The boundary is therefore checkable: LOSSY iff REVIEW by the
  # chain, tip resolved, origin/<default> present, the count succeeded and is
  # positive, and the PR state is neither MERGED nor OPEN.
  case "$tier" in
  PROTECTED | WORKTREE | SAFE | LIKELY-SAFE)
    loss_line="not assessed ($tier)"
    ;;
  *)
    if [[ -z "$local_tip" ]]; then
      loss_line="undetermined (tip unresolved)"
    elif [[ -z "$ahead_default" ]]; then
      loss_line="undetermined (no origin/${DEFAULT_BRANCH} to compare against)"
    elif ! branch_loss_count; then
      lost=""
      loss_line="undetermined (could not count commits absent from every remote ref and tag)"
    elif [[ "$lost" -eq 0 ]]; then
      loss_line="none (every commit is on a remote ref or a tag)"
    else
      loss_line="${lost} commits only on this branch"
      case "${PR_STATE[$branch]:-}" in
      MERGED)
        # A squash merge lands the work under a new SHA, so the count above
        # overstates what a deletion loses; the tip drift already put the
        # branch in REVIEW and it stays there.
        loss_line+=" (PR merged; count unreliable after a squash, stays REVIEW)"
        ;;
      OPEN)
        loss_line+=" (PR open, stays REVIEW)"
        ;;
      *)
        if [[ -n "$OP_PATH" ]]; then
          reason="operation in progress: $OP_PATH"
        else
          tier="LOSSY"
          LOSSY_BRANCHES+=("$branch")
          LOSSY_COUNTS+=("$lost")
          LOSSY_REASONS+=("$reason")
          LOSSY_TIPS+=("$local_tip")
        fi
        ;;
      esac
    fi
    ;;
  esac

  case "$tier" in
  PROTECTED) prot=$((prot + 1)) ;;
  WORKTREE) wt=$((wt + 1)) ;;
  SAFE) safe=$((safe + 1)) ;;
  LIKELY-SAFE) likely=$((likely + 1)) ;;
  LOSSY) lossy=$((lossy + 1)) ;;
  *) review=$((review + 1)) ;;
  esac

  if [[ -n "${PR_STATE[$branch]:-}" && "$pr_line" == "none" ]]; then
    pr_line="#${PR_NUM[$branch]} ${PR_STATE[$branch]}"
  fi

  if [[ "$no_upstream" == 1 ]]; then
    if [[ -n "$ahead_default" ]]; then
      unpushed_line="no upstream, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
    else
      unpushed_line="no upstream (no origin/${DEFAULT_BRANCH} to compare)"
    fi
  else
    if [[ $bulk -eq 0 ]]; then
      ahead_up="$(git -C "$REPO_ROOT" rev-list --count "${branch}@{upstream}..refs/heads/${branch}" 2>/dev/null | tr -d '\r')"
      behind_up="$(git -C "$REPO_ROOT" rev-list --count "refs/heads/${branch}..${branch}@{upstream}" 2>/dev/null | tr -d '\r')"
    fi
    unpushed_line="${ahead_up:-0} ahead of ${upstream}"
  fi

  printf 'Branch: %s\n' "$branch"
  printf 'Tip: %s\n' "${local_tip:-unresolved}"
  printf 'Tier: %s\n' "$tier"
  printf 'Age days: %s\n' "$age_days"
  printf 'PR: %s\n' "$pr_line"
  printf 'Unpushed: %s\n' "$unpushed_line"
  printf 'Loss: %s\n' "$loss_line"
  printf 'Reason: %s\n' "$reason"
  [[ -n "$landed_reason" ]] && printf 'Landed: %s\n' "$landed_reason"
  [[ "$tier" == WORKTREE ]] && printf 'Worktree: %s\n' "${WORKTREE_PATH[$branch]}"

  if [[ -n "$local_tip" ]]; then
    printf -v row '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
      "$branch" "$local_tip" "$tier" "$pr_line" "${upstream:-none}" \
      "${ahead_up:--}" "${behind_up:--}" "${ahead_default:--}" "${landed_reason:--}" "$CAPTURED_AT"
    capture_line "$row"
    CAPTURE_ROWS=$((CAPTURE_ROWS + 1))
  fi
}

for line in ${REF_RECORDS[@]+"${REF_RECORDS[@]}"}; do
  [[ -z "$line" ]] && continue
  IFS=$REC_SEP read -r refname branch tip otype ts upfull upshort track <<<"$line"
  age_days=$(((NOW - ts) / 86400))
  classify_branch "$branch" "$age_days" "$refname" "$tip" "$otype" "$upfull" "$upshort" "$track"
done

# The loss block: the LOSSY set again, as its own surface. It is printed even
# when empty so a reader can tell "no branch loses work" from "the block was
# never produced". Per branch: the count, the chain's reason, the tip, and the
# commits that would be lost (capped; the remainder is counted, not dropped
# silently).
if [[ ${#LOSSY_BRANCHES[@]} -eq 0 ]]; then
  printf 'LossBlock: 0 branches lose work if deleted\n'
else
  printf 'LossBlock: %s branches lose work if deleted; confirm them as their own decision, never with the SAFE/LIKELY-SAFE set\n' "${#LOSSY_BRANCHES[@]}"
  for i in "${!LOSSY_BRANCHES[@]}"; do
    b="${LOSSY_BRANCHES[$i]}"
    n="${LOSSY_COUNTS[$i]}"
    printf 'LossBranch: %s %s commits only on this branch (%s) tip %s\n' "$b" "$n" "${LOSSY_REASONS[$i]}" "${LOSSY_TIPS[$i]}"
    shown=0
    while IFS= read -r cl; do
      cl="${cl%$'\r'}"
      [[ -z "$cl" ]] && continue
      printf 'LossCommit: %s %s\n' "$b" "$cl"
      shown=$((shown + 1))
    done < <(git -C "$REPO_ROOT" log --format='%h %s' -n "$LOSS_COMMITS_SHOWN" "refs/heads/$b" --not --remotes --tags 2>/dev/null)
    if [[ "$n" -gt "$shown" ]]; then
      printf 'LossCommit: %s and %s more\n' "$b" "$((n - shown))"
    fi
  done
fi
printf 'LossBlockEnd: %s\n' "${#LOSSY_BRANCHES[@]}"

# Seal the capture: rename the .part into place only after a row count on the
# written file agrees with the rows this run produced. A short write (disk full,
# a vanished mount) therefore surfaces as TipCaptureError, never as a capture
# that silently lacks some of the branches the report above lists. A row is
# counted by shape: ten columns, a commit id in the second, this run's stamp in
# the last (a truncated row fails that test); a branch name beginning with `#`
# is a row like any other.
if [[ -z "$CAPTURE_ERROR" ]]; then
  written="$(awk -F'\t' -v at="$CAPTURED_AT" \
    'NF == 10 && $2 ~ /^[0-9a-f]+$/ && length($2) >= 40 && $10 == at { n++ } END { print n + 0 }' \
    "$CAPTURE_TMP" 2>/dev/null | tr -d '\r')"
  if [[ "${written:-x}" != "$CAPTURE_ROWS" ]]; then
    CAPTURE_ERROR="short write: expected $CAPTURE_ROWS rows, found ${written:-0} in $CAPTURE_TMP"
  elif ! mv -f "$CAPTURE_TMP" "$CAPTURE_PATH" 2>/dev/null; then
    CAPTURE_ERROR="cannot rename $CAPTURE_TMP into place"
  fi
fi
if [[ -n "$CAPTURE_ERROR" ]]; then
  [[ $CAPTURE_TMP_OWNED -eq 1 ]] && rm -f "$CAPTURE_TMP" 2>/dev/null
  printf 'TipCaptureError: %s\n' "$CAPTURE_ERROR"
else
  printf 'TipCapture: %s\n' "$CAPTURE_PATH"
fi

printf 'Summary: protected=%s worktree=%s safe=%s likely-safe=%s lossy=%s review=%s\n' "$prot" "$wt" "$safe" "$likely" "$lossy" "$review"
exit 0
