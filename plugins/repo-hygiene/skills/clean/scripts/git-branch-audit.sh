#!/usr/bin/env bash
# shellcheck disable=SC2154
# Exit: 0 (2 on a usage error).
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/clean-common.sh source=lib/cleanup-paths.sh
source "$SCRIPT_DIR/lib/clean-common.sh"
# shellcheck source=lib/git-noninteractive.sh
source "$SCRIPT_DIR/lib/git-noninteractive.sh"
# shellcheck source=lib/batch-common.sh
source "$SCRIPT_DIR/lib/batch-common.sh"

usage() {
  cat <<'EOF'
git-branch-audit.sh - emit branch audit facts for the clean git tier.

Usage:
  git-branch-audit.sh [--capture-file PATH | --read-only]
  git-branch-audit.sh --remote
  git-branch-audit.sh [--repo DIR...]... [--repos-from FILE|-]...
                      [--skip ENTRY]... [--skip-from FILE]...
                      [--capture-file PATH | --read-only] [--remote]
  git-branch-audit.sh --remote-families [--repo DIR...]... [--repos-from FILE|-]...
                      [--skip ENTRY]... [--skip-from FILE]...
  git-branch-audit.sh --help

  --capture-file PATH  write the branch-tip capture to PATH instead of the
                       default <git-common-dir>/repo-hygiene/branch-tips/<utc-stamp>-<pid>.tsv
  --read-only          write no capture and no object (no file, no .part, no loose
                       object from the landed proof); git-branch-delete.sh will
                       refuse to act on this run
  --remote             audit origin's branches from `git ls-remote --heads origin`
                       against merged PRs (`gh pr list --state merged --head`);
                       writes no capture
  --remote-families    report refs/remotes/origin/* by branch family with a retention
                       verdict, instead of the local audit (see below)
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
is a usage error (exit 2). With --remote, a second clone of one origin is reported
`skipped duplicate of <path>` and counted in duplicate=, since it would list the
same remote branches; a local audit reads each clone's own branches, so it audits
every clone. Deletion is never batched: run git-branch-delete.sh
from inside the audited repo with that repo's capture.

Leading: PRCount or PRDataUnavailable, optional PRDataTruncated. Then
`MainCheckout: <branch | detached at <sha>>`, `MainCheckoutDirty: <n>` and a
`MainCheckoutOperation: <name> <path>` per merge, rebase, cherry-pick, revert or
bisect in progress; any of those prints `OperationInProgress: <path>` and demotes
SAFE, LIKELY-SAFE and LOSSY to REVIEW. These describe the checkout the audit runs
from (a linked worktree when it runs from one); an operation in another
worktree is not detected.
Per branch: Branch, Tip, Tier, Age days, PR, Unpushed, Loss, Reason, Landed (a
landed branch only, `Landed: <proof>`), Family; a WORKTREE branch adds `Worktree: <path>`, the worktree that has it checked out.
Family: agent (agent-<hex>), claude (claude/*), plan (plan/*), stranded
(stranded/*), pre-wipe (pre-wipe/*), or none. Information only; never a tier input.
Tiers: PROTECTED, WORKTREE, SAFE, LIKELY-SAFE, LOSSY, REVIEW. A branch whose work
origin/<default> already holds, by patch-id (`git cherry`), by tree equality, or
as one squashed diff, is LIKELY-SAFE with a `Landed:` line, unless its PR is OPEN
or CLOSED. The squash check writes one unreferenced loose commit object per
branch that reaches it (`git gc` prunes it), and none under --read-only.
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

--read-only replaces the capture line with `TipCaptureSkipped: <why>`.

--remote prints `RemoteBranches: <n>` (or `RemoteError: <why>` when the live list
could not be read), then per origin branch RemoteBranch, RemoteTip, RemoteTier,
RemotePR, RemoteReason, and RemoteAhead for a drift, then `RemoteSummary:`.
RemoteTier: PROTECTED, MERGED (tip is a merged PR's head), MERGED-DRIFT (tip
differs from every merged PR head: commits landed after the merge),
NO-MERGED-PR, or UNKNOWN (gh or jq absent, or the lookup failed). RemoteAhead
counts commits past the PR head, says diverged when the PR head is not an ancestor of the tip, or says why it cannot (an unfetched object; the
audit never fetches). In the fleet form --remote and --read-only apply to every repo.
--remote and --remote-families are separate reports and cannot combine.

--remote-families is report only and takes the place of everything above: it reads
refs/remotes/origin/* as last fetched (no fetch is run), skips origin/HEAD, the
default branch and the protected patterns, writes no capture (so --capture-file is a
usage error) and gives git-branch-delete.sh nothing to act on. It works without gh,
leaving PRDataUnavailable in place, and then no branch reads as landed. After the
PR-map lines and a `Mode:` line, each branch is `RemoteBranch`, `Tip`, `Age days`
(the tip's committer date), `Family`, `PR`, `Landed` (`no`, or the proof: a MERGED
PR whose head is the tip or has the tip as an ancestor), `Retention` and `Reason`;
`RemoteSummary:` closes the run. Retention is one of:
  CANDIDATE          the family rule releases it and the work landed or is on another ref
  KEEP               within its window, checked out in a worktree, or has an open PR
  KEEP-UNIQUE        released by the family rule, but not landed and on no other ref
  KEEP-UNDETERMINED  released, but the check for another ref failed
  n/a                family none: no retention rule
Family rules (a tip is older than N days by committer date; the windows are the
defaults in lib/cleanup-paths.sh and each is overridden by an environment
variable holding a whole number of days):
  pre-wipe/*  30 days  CLEAN_RETENTION_PREWIPE_DAYS
  claude/*    30 days  CLEAN_RETENTION_CLAUDE_DAYS
  plan/*      90 days  CLEAN_RETENTION_PLAN_DAYS
  stranded/*  30 days  CLEAN_RETENTION_STRANDED_DAYS
  agent-<hex> no window: released once no worktree has it checked out (owner:
              source-control:worktree cleanup)
"On another ref" is `git rev-list <tip> --not <every other ref>` being empty. With
--repo / --repos-from each repository is reported the same way.

Does not delete branches. Exit: 0 (2 on a usage error).
EOF
}

CAPTURE_ARG=""
FLEET=0
READ_ONLY=0
REMOTE=0
REMOTE_FAMILIES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --remote-families)
    REMOTE_FAMILIES=1
    shift
    ;;
  --capture-file)
    if [[ -z "${2:-}" ]]; then
      echo "git-branch-audit.sh: --capture-file requires a value" >&2
      exit 2
    fi
    CAPTURE_ARG="$2"
    shift 2
    ;;
  --read-only)
    READ_ONLY=1
    shift
    ;;
  --remote)
    REMOTE=1
    shift
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

if [[ -n "$CAPTURE_ARG" && ($READ_ONLY -eq 1 || $REMOTE -eq 1) ]]; then
  echo "git-branch-audit.sh: --capture-file cannot combine with --read-only or --remote (neither writes a capture)" >&2
  exit 2
fi
if [[ $REMOTE_FAMILIES -eq 1 && -n "$CAPTURE_ARG" ]]; then
  echo "git-branch-audit.sh: --remote-families writes no capture; drop --capture-file" >&2
  exit 2
fi
if [[ $REMOTE -eq 1 && $REMOTE_FAMILIES -eq 1 ]]; then
  echo "git-branch-audit.sh: --remote and --remote-families are separate reports; pick one" >&2
  exit 2
fi
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
  [[ $REMOTE -eq 1 ]] && batch_dedupe_clones
  if [[ -n "$CAPTURE_ARG" && ${#BATCH_TOPS[@]} -gt 1 ]]; then
    echo "git-branch-audit.sh: --capture-file names one file and cannot serve ${#BATCH_TOPS[@]} repos; omit it so each repo writes its own default capture" >&2
    exit 2
  fi
  child_args=()
  [[ -n "$CAPTURE_ARG" ]] && child_args+=(--capture-file "$CAPTURE_ARG")
  [[ $READ_ONLY -eq 1 ]] && child_args+=(--read-only)
  [[ $REMOTE -eq 1 ]] && child_args+=(--remote)
  [[ $REMOTE_FAMILIES -eq 1 ]] && child_args+=(--remote-families)
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

remote_audit() {
  local heads tip ref name tier reason pr_line ahead_line raw rows pick pr oid n origin_url
  local prot=0 merged=0 drift=0 nomerge=0 unknown=0 why=""
  if ! heads="$(clean_git_noninteractive -C "$REPO_ROOT" ls-remote --heads origin 2>/dev/null)"; then
    printf 'RemoteError: git ls-remote --heads origin failed (remote unreachable)\n'
    return
  fi
  heads="${heads//$'\r'/}"
  origin_url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null | tr -d '\r')"
  command -v gh >/dev/null 2>&1 || why="gh not on PATH"
  if [[ -z "$why" ]] && ! command -v jq >/dev/null 2>&1; then why="jq not on PATH"; fi
  printf 'RemoteBranches: %s\n' "$(grep -c . <<<"$heads")"
  while IFS=$'\t' read -r tip ref; do
    [[ "$ref" == refs/heads/* ]] || continue
    name="${ref#refs/heads/}"
    pr_line="none" ahead_line=""
    if [[ "$name" == "$DEFAULT_BRANCH" ]]; then
      tier=PROTECTED reason="default branch"
    elif clean_branch_matches_protected_pattern "$name"; then
      tier=PROTECTED reason="protected pattern"
    elif [[ -n "$why" ]]; then
      tier=UNKNOWN reason="merged-PR lookup unavailable ($why)"
    elif ! raw="$(gh pr list --repo "$origin_url" --state merged --head "$name" --json number,headRefOid --limit 100 2>/dev/null </dev/null)" ||
      ! rows="$(printf '%s' "$raw" | jq -r 'if type == "array" then .[] | [.number, .headRefOid] | @tsv else error("not an array") end' 2>/dev/null | tr -d '\r')"; then
      tier=UNKNOWN reason="merged-PR lookup failed (unauthenticated, no GitHub remote, or API error)"
    else
      pick="$(awk -F'\t' -v tip="$tip" '$2 == tip { print $1 "\t" $2; found = 1; exit } $1 + 0 > best { best = $1 + 0; bo = $2 } END { if (!found && best) print best "\t" bo }' <<<"$rows")"
      if [[ -z "$pick" ]]; then
        tier=NO-MERGED-PR reason="no merged PR has this branch as its head"
      else
        IFS=$'\t' read -r pr oid <<<"$pick"
        if [[ "$oid" == "$tip" ]]; then
          tier=MERGED reason="tip is the merged PR's head"
          pr_line="#$pr MERGED"
        else
          tier=MERGED-DRIFT reason="tip differs from the merged PR's head (commits since the merge)"
          pr_line="#$pr MERGED (head $oid)"
          if git -C "$REPO_ROOT" cat-file -e "$oid^{commit}" 2>/dev/null && git -C "$REPO_ROOT" cat-file -e "$tip^{commit}" 2>/dev/null; then
            if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$oid" "$tip" 2>/dev/null; then
              reason="tip differs from the merged PR's head and does not descend from it (branch rewritten after the merge)"
              ahead_line="diverged (the PR head is not an ancestor of the tip)"
            elif n="$(git -C "$REPO_ROOT" rev-list --count "$oid..$tip" 2>/dev/null | tr -d '\r')" && [[ -n "$n" ]]; then
              ahead_line="$n commits past the PR head"
            else
              ahead_line="not computable"
            fi
          else
            ahead_line="not computable (tip or PR head not fetched locally; this audit never fetches)"
          fi
        fi
      fi
    fi
    case "$tier" in
    PROTECTED) prot=$((prot + 1)) ;;
    MERGED) merged=$((merged + 1)) ;;
    MERGED-DRIFT) drift=$((drift + 1)) ;;
    NO-MERGED-PR) nomerge=$((nomerge + 1)) ;;
    *) unknown=$((unknown + 1)) ;;
    esac
    printf 'RemoteBranch: %s\nRemoteTip: %s\nRemoteTier: %s\nRemotePR: %s\nRemoteReason: %s\n' "$name" "$tip" "$tier" "$pr_line" "$reason"
    [[ -n "$ahead_line" ]] && printf 'RemoteAhead: %s\n' "$ahead_line"
  done <<<"$heads"
  printf 'RemoteSummary: protected=%s merged=%s merged-drift=%s no-merged-pr=%s unknown=%s\n' "$prot" "$merged" "$drift" "$nomerge" "$unknown"
}
if [[ $REMOTE -eq 1 ]]; then
  remote_audit
  exit 0
fi

declare -A PR_STATE=()
declare -A PR_NUM=()
declare -A PR_REFOID=()
PR_MAP_FILE="$(mktemp 2>/dev/null)" || PR_MAP_FILE="${TMPDIR:-/tmp}/clean-pr-map.$$"
PROOF_OBJDIR="" REAL_OBJDIR=""
if [[ $READ_ONLY -eq 1 ]]; then
  PROOF_OBJDIR="$(mktemp -d 2>/dev/null)"
  REAL_OBJDIR="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path objects 2>/dev/null | tr -d '\r')"
fi
trap 'rm -f "$PR_MAP_FILE"; [[ -z "$PROOF_OBJDIR" ]] || rm -rf "$PROOF_OBJDIR"' EXIT

landed_proof() {
  if [[ $READ_ONLY -eq 0 ]]; then
    clean_landed_proof "$REPO_ROOT" "$DEFAULT_BRANCH" "$1"
  elif [[ -n "$PROOF_OBJDIR" && -n "$REAL_OBJDIR" ]]; then
    GIT_OBJECT_DIRECTORY="$PROOF_OBJDIR" GIT_ALTERNATE_OBJECT_DIRECTORIES="$REAL_OBJDIR" \
      clean_landed_proof "$REPO_ROOT" "$DEFAULT_BRANCH" "$1"
  else
    return 1
  fi
}
PR_MAP_STATUS="$(clean_pr_map "$PR_MAP_FILE" 'headRefName,state,number,headRefOid')"
[[ -n "$PR_MAP_STATUS" ]] && printf '%s\n' "$PR_MAP_STATUS"
PR_MAP_INCOMPLETE=0
[[ "$PR_MAP_STATUS" == *PRDataUnavailable* || "$PR_MAP_STATUS" == *PRDataTruncated* ]] && PR_MAP_INCOMPLETE=1
if [[ -f "$PR_MAP_FILE" ]]; then
  while IFS=$'\t' read -r head state num refoid; do
    [[ -z "$head" ]] && continue
    PR_STATE["$head"]="$state"
    PR_NUM["$head"]="$num"
    PR_REFOID["$head"]="$refoid"
  done <"$PR_MAP_FILE"
fi

branch_family() {
  case "$1" in
  claude/*) printf claude ;;
  plan/*) printf plan ;;
  stranded/*) printf stranded ;;
  pre-wipe/*) printf pre-wipe ;;
  *)
    if [[ "$1" =~ ^agent-[0-9a-f]+$ ]]; then printf agent; else printf none; fi
    ;;
  esac
}

remote_families_report() {
  local v line name tip otype ts age_days family days state pr_line landed num oid head refoid
  local verdict why expired unique_out n_total=0 n_cand=0 n_keep=0 n_unique=0 n_unknown=0 n_na=0
  local -A open_pr=() merged_prs=() wt=() n_fam=()
  for v in CLEAN_RETENTION_PREWIPE_DAYS CLEAN_RETENTION_CLAUDE_DAYS CLEAN_RETENTION_PLAN_DAYS CLEAN_RETENTION_STRANDED_DAYS; do
    if ! [[ "${!v}" =~ ^[0-9]+$ ]]; then
      echo "git-branch-audit.sh: $v must be a whole number of days, got '${!v}'" >&2
      exit 2
    fi
  done
  while IFS=$'\t' read -r head state num refoid; do
    case "$state" in
    OPEN) open_pr["$head"]="$num" ;;
    MERGED) merged_prs["$head"]+="$num $refoid"$'\n' ;;
    *) ;;
    esac
  done <"$PR_MAP_FILE"
  while IFS= read -r line; do
    [[ -n "$line" ]] && wt["${line%%$'\t'*}"]="${line#*$'\t'}"
  done < <(clean_worktree_branch_paths "$REPO_ROOT")

  printf 'Mode: remote-families (report only; deletes nothing, fetches nothing, writes no TipCapture; refs are as last fetched)\n'
  local now
  now=$(date +%s)
  while IFS=$'\x1f' read -r name tip otype ts; do
    name="${name#refs/remotes/origin/}"
    [[ -z "$name" || "$name" == HEAD || "$name" == "$DEFAULT_BRANCH" || "$otype" != commit ]] && continue
    clean_branch_matches_protected_pattern "$name" && continue
    n_total=$((n_total + 1))
    age_days=$(((now - ts) / 86400))
    family="$(branch_family "$name")"
    n_fam["$family"]=$((${n_fam[$family]:-0} + 1))

    landed="" pr_line="none"
    while read -r num oid; do
      [[ -n "$num" ]] || continue
      if [[ "$oid" == "$tip" ]]; then
        landed="PR #$num merged, its head is the tip"
      elif git -C "$REPO_ROOT" rev-parse --verify --quiet "${oid}^{commit}" >/dev/null 2>&1 &&
        git -C "$REPO_ROOT" merge-base --is-ancestor "$tip" "$oid" 2>/dev/null; then
        landed="PR #$num merged, the tip is an ancestor of its head"
      fi
      if [[ -n "$landed" ]]; then
        pr_line="#$num MERGED"
        break
      fi
    done <<<"${merged_prs[$name]:-}"
    if [[ -n "${open_pr[$name]+x}" ]]; then
      pr_line="#${open_pr[$name]} OPEN"
    elif [[ "$pr_line" == none && -n "${PR_STATE[$name]:-}" ]]; then
      pr_line="#${PR_NUM[$name]} ${PR_STATE[$name]}"
    fi

    verdict=KEEP expired=0 why=""
    if [[ "$family" != none && -n "${open_pr[$name]+x}" ]]; then
      why="PR open"
    else
      case "$family" in
      agent)
        if [[ -n "${wt[$name]+x}" ]]; then
          why="checked out in worktree ${wt[$name]}"
        else
          expired=1 why="no worktree has it checked out (owner: source-control:worktree cleanup)"
        fi
        ;;
      pre-wipe | claude | plan | stranded)
        case "$family" in
        pre-wipe) days="$CLEAN_RETENTION_PREWIPE_DAYS" ;;
        claude) days="$CLEAN_RETENTION_CLAUDE_DAYS" ;;
        plan) days="$CLEAN_RETENTION_PLAN_DAYS" ;;
        *) days="$CLEAN_RETENTION_STRANDED_DAYS" ;;
        esac
        if [[ "$age_days" -gt "$days" ]]; then
          expired=1 why="tip is ${age_days}d old, past the ${days}d retention for $family"
        else
          why="tip is ${age_days}d old, within the ${days}d retention for $family"
        fi
        ;;
      *)
        verdict="n/a" why="no retention rule for this family"
        ;;
      esac
    fi
    if [[ $expired -eq 1 ]]; then
      if [[ $PR_MAP_INCOMPLETE -eq 1 ]]; then
        verdict=KEEP-UNDETERMINED why+="; PR data is incomplete, so an open PR cannot be ruled out"
      elif [[ -n "$landed" ]]; then
        verdict=CANDIDATE why+="; landed"
      elif ! unique_out="$(git -C "$REPO_ROOT" rev-list -n 1 "$tip" --not --exclude="refs/remotes/origin/$name" --all 2>/dev/null)"; then
        verdict=KEEP-UNDETERMINED why+="; could not check whether another ref holds the tip"
      elif [[ -n "$unique_out" ]]; then
        verdict=KEEP-UNIQUE why+="; not landed and no other ref holds the tip"
      else
        verdict=CANDIDATE why+="; another ref holds the tip"
      fi
    fi
    case "$verdict" in
    CANDIDATE) n_cand=$((n_cand + 1)) ;;
    KEEP) n_keep=$((n_keep + 1)) ;;
    KEEP-UNIQUE) n_unique=$((n_unique + 1)) ;;
    KEEP-UNDETERMINED) n_unknown=$((n_unknown + 1)) ;;
    *) n_na=$((n_na + 1)) ;;
    esac

    printf 'RemoteBranch: %s\n' "$name"
    printf 'Tip: %s\n' "$tip"
    printf 'Age days: %s\n' "$age_days"
    printf 'Family: %s\n' "$family"
    printf 'PR: %s\n' "$pr_line"
    printf 'Landed: %s\n' "${landed:-no}"
    printf 'Retention: %s\n' "$verdict"
    printf 'Reason: %s\n' "$why"
  done < <(git -C "$REPO_ROOT" for-each-ref refs/remotes/origin/ \
    --format='%(refname)%1f%(objectname)%1f%(objecttype)%1f%(committerdate:unix)' 2>/dev/null | tr -d '\r')
  printf 'RemoteSummary: branches=%s candidate=%s keep=%s keep-unique=%s keep-undetermined=%s no-rule=%s\n' \
    "$n_total" "$n_cand" "$n_keep" "$n_unique" "$n_unknown" "$n_na"
  printf 'Families: agent=%s claude=%s plan=%s stranded=%s pre-wipe=%s none=%s\n' \
    "${n_fam[agent]:-0}" "${n_fam[claude]:-0}" "${n_fam[plan]:-0}" "${n_fam[stranded]:-0}" "${n_fam["pre-wipe"]:-0}" "${n_fam[none]:-0}"
}
if [[ $REMOTE_FAMILIES -eq 1 ]]; then
  remote_families_report
  exit 0
fi

CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMON_DIR="$(clean_git_common_dir "$REPO_ROOT")" || COMMON_DIR=""
CAPTURE_ERROR=""
CAPTURE_ROWS=0
if [[ $READ_ONLY -eq 1 ]]; then
  CAPTURE_PATH=""
elif [[ -n "$CAPTURE_ARG" ]]; then
  CAPTURE_PATH="$CAPTURE_ARG"
elif [[ -n "$COMMON_DIR" ]]; then
  CAPTURE_PATH="$COMMON_DIR/repo-hygiene/branch-tips/$(date -u +%Y%m%dT%H%M%SZ)-$$.tsv"
else
  CAPTURE_PATH=""
  CAPTURE_ERROR="cannot resolve the git common dir for a default capture location; pass --capture-file PATH"
fi
CAPTURE_TMP="${CAPTURE_PATH}.part"
CAPTURE_TMP_OWNED=0
if [[ $READ_ONLY -eq 0 && -z "$CAPTURE_ERROR" ]]; then
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
  [[ $READ_ONLY -eq 1 || -n "$CAPTURE_ERROR" ]] && return 0
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

MAIN_HEAD_LINE="$CURRENT_BRANCH"
[[ -n "$MAIN_HEAD_LINE" ]] || MAIN_HEAD_LINE="detached at $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null | tr -d '\r')"
printf 'MainCheckout: %s\n' "$MAIN_HEAD_LINE"
printf 'MainCheckoutDirty: %s\n' "$(git -C "$REPO_ROOT" --no-optional-locks status --porcelain --untracked-files=all 2>/dev/null | wc -l | tr -d ' \r')"
OP_PATH=""
for op_name in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
  op_file="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path "$op_name" 2>/dev/null | tr -d '\r')"
  if [[ -n "$op_file" && -e "$op_file" ]]; then
    printf 'MainCheckoutOperation: %s %s\n' "$op_name" "$op_file"
    OP_PATH="${OP_PATH:-$op_file}"
  fi
done
[[ -n "$OP_PATH" ]] && printf 'OperationInProgress: %s\n' "$OP_PATH"

declare -A WORKTREE_PATH=() GONE_SET=() MERGED_SET=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  WORKTREE_PATH["${line%%$'\t'*}"]="${line#*$'\t'}"
done < <(clean_worktree_branch_paths "$REPO_ROOT")
while IFS= read -r line; do
  [[ -n "$line" ]] && GONE_SET["$line"]=1
done < <(git -C "$REPO_ROOT" branch -vv 2>/dev/null | grep ': gone]' | awk '{print $1}' | tr -d '\r')
while IFS= read -r line; do
  [[ -n "$line" ]] && MERGED_SET["$line"]=1
done < <(git -C "$REPO_ROOT" branch --merged "origin/${DEFAULT_BRANCH}" 2>/dev/null | sed 's/^[ *]*//' | grep -v "^${DEFAULT_BRANCH}$" | tr -d '\r')

ORIGIN_DEFAULT=0
if git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/${DEFAULT_BRANCH}" >/dev/null 2>&1; then
  ORIGIN_DEFAULT=1
fi
REC_SEP=$'\x1f'
mapfile -t REF_RECORDS < <(git -C "$REPO_ROOT" for-each-ref refs/heads/ \
  --format='%(refname)%1f%(refname:short)%1f%(objectname)%1f%(objecttype)%1f%(committerdate:unix)%1f%(upstream)%1f%(upstream:short)%1f%(upstream:track)' 2>/dev/null | tr -d '\r')

bulk_record_ok() { # <refname> <short name> <object type>
  [[ "$1" == "refs/heads/$2" && "$3" == commit ]]
}

declare -A COUNT=()
load_counts() {
  local key="$1" out oid n
  shift
  out="$(printf '%s' "$BULK_TIPS" | clean_unreached_counts "$REPO_ROOT" "$@")" || return 0
  while read -r oid n; do
    [[ -n "$oid" ]] && COUNT["$key:$oid"]="$n"
  done <<<"$out"
}
BULK_TIPS="" GONE_UPSTREAMS="" DRIFT_PAIRS=""
for line in ${REF_RECORDS[@]+"${REF_RECORDS[@]}"}; do
  IFS=$REC_SEP read -r refname branch tip otype _ upfull _ track <<<"$line"
  bulk_record_ok "$refname" "$branch" "$otype" || continue
  BULK_TIPS+="$tip"$'\n'
  [[ -n "$upfull" && "$track" == "[gone]" ]] && GONE_UPSTREAMS+="$upfull"$'\n'
  [[ "${PR_STATE[$branch]:-}" == MERGED && -n "${PR_REFOID[$branch]:-}" && "$tip" != "${PR_REFOID[$branch]}" ]] &&
    DRIFT_PAIRS+="$tip ${PR_REFOID[$branch]}"$'\n'
done

declare -A ANCESTOR=()
load_ancestors() {
  local pairs t h i graph out heads=() present=()
  mapfile -t pairs <<<"${DRIFT_PAIRS%$'\n'}"
  for i in "${!pairs[@]}"; do heads+=("${pairs[$i]#* }"); done
  mapfile -t present < <(printf '%s\n' "${heads[@]}" | git -C "$REPO_ROOT" cat-file --batch-check 2>/dev/null | tr -d '\r')
  [[ ${#present[@]} -eq ${#heads[@]} ]] || return 0
  local ids="" ok=""
  for i in "${!pairs[@]}"; do
    if [[ "${present[$i]}" != *" commit "* ]]; then
      ANCESTOR["${pairs[$i]% *}:${heads[$i]}"]=0
      continue
    fi
    ok+="${pairs[$i]}"$'\n'
    ids+="${pairs[$i]% *}"$'\n'"${heads[$i]}"$'\n'
  done
  [[ -n "$ok" ]] || return 0
  graph="$(printf '%s' "$ids" | git -C "$REPO_ROOT" rev-list --parents --stdin 2>/dev/null)" || return 0
  out="$(printf '%s--\n%s\n' "$ok" "$graph" | awk '
    !mark && $0 == "--" { mark = 1; next }
    !mark { n++; tip[n] = $1; head[n] = $2; next }
    NF { parents[$1] = substr($0, length($1) + 2) }
    END {
      for (q = 1; q <= n; q++) {
        found = 0; sp = 0; stack[sp++] = head[q]; seen[head[q]] = q
        while (sp > 0 && !found) {
          c = stack[--sp]
          if (c == tip[q]) { found = 1; break }
          k = split(parents[c], ps, " ")
          for (i = 1; i <= k; i++) if (seen[ps[i]] != q) { seen[ps[i]] = q; stack[sp++] = ps[i] }
        }
        print tip[q], head[q], found
      }
    }')" || return 0
  while read -r t h i; do
    [[ -n "$i" ]] && ANCESTOR["$t:$h"]="$i"
  done <<<"$out"
}
[[ -n "$DRIFT_PAIRS" ]] && load_ancestors
if [[ $ORIGIN_DEFAULT -eq 1 ]]; then
  load_counts ahead "origin/${DEFAULT_BRANCH}"
  load_counts loss --remotes --tags
fi

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

LOSSY_BRANCHES=()
LOSSY_COUNTS=()
LOSSY_REASONS=()
LOSSY_TIPS=()
LOSS_COMMITS_SHOWN="${CLEAN_LOSS_COMMITS_SHOWN:-10}"
[[ "$LOSS_COMMITS_SHOWN" =~ ^[0-9]+$ ]] || LOSS_COMMITS_SHOWN=10

bulk_facts() {
  bulk_record_ok "$refname" "$branch" "$otype" || return 1
  local up="" a="" b=""
  if [[ -n "$upfull" && "$track" == "[gone]" ]]; then
    [[ -z "${UPSTREAM_EXISTS[$upfull]+x}" ]] || return 1
  elif [[ -n "$upfull" ]]; then
    up="$upshort" a=0 b=0
    if [[ "$track" =~ ^\[ahead\ ([0-9]+)\]$ ]]; then
      a="${BASH_REMATCH[1]}"
    elif [[ "$track" =~ ^\[behind\ ([0-9]+)\]$ ]]; then
      b="${BASH_REMATCH[1]}"
    elif [[ "$track" =~ ^\[ahead\ ([0-9]+),\ behind\ ([0-9]+)\]$ ]]; then
      a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[2]}"
    elif [[ -n "$track" ]]; then
      return 1
    fi
  fi
  local_tip="$tip" upstream="$up" ahead_up="$a" behind_up="$b"
}

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
  local loss_line lost="" row ancestor landed_reason=""

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
  if [[ $ORIGIN_DEFAULT -eq 1 ]]; then
    if [[ $bulk -eq 1 && -n "${COUNT["ahead:$local_tip"]+x}" ]]; then
      ahead_default="${COUNT["ahead:$local_tip"]}"
    else
      ahead_default="$(git -C "$REPO_ROOT" rev-list --count "origin/${DEFAULT_BRANCH}..refs/heads/${branch}" 2>/dev/null | tr -d '\r')"
    fi
  fi

  if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
    tier=PROTECTED reason="current branch"
  elif [[ "$branch" == "$DEFAULT_BRANCH" ]]; then
    tier=PROTECTED reason="default branch"
  elif clean_branch_matches_protected_pattern "$branch"; then
    tier=PROTECTED reason="protected pattern"
  elif [[ -n "${WORKTREE_PATH[$branch]+x}" ]]; then
    tier=WORKTREE reason="checked out in worktree — clean up the worktree first"
  elif [[ "${PR_STATE[$branch]:-}" == "MERGED" ]]; then
    if [[ -n "${PR_REFOID[$branch]:-}" && -n "$local_tip" && "$local_tip" != "${PR_REFOID[$branch]}" ]]; then
      pr_line="#${PR_NUM[$branch]} MERGED (tip drift)"
      if [[ $bulk -eq 1 && -n "${ANCESTOR["$local_tip:${PR_REFOID[$branch]}"]+x}" ]]; then
        ancestor="${ANCESTOR["$local_tip:${PR_REFOID[$branch]}"]}"
      elif git -C "$REPO_ROOT" rev-parse --verify --quiet "${PR_REFOID[$branch]}^{commit}" >/dev/null 2>&1 &&
        git -C "$REPO_ROOT" merge-base --is-ancestor "$local_tip" "${PR_REFOID[$branch]}" 2>/dev/null; then
        ancestor=1
      else
        ancestor=0
      fi
      if [[ $ancestor -eq 1 ]]; then
        tier=SAFE reason="PR merged (tip is an ancestor of the merged head)"
      else
        tier=REVIEW reason="PR merged but branch has commits since merge"
      fi
    else
      tier=SAFE reason="PR merged" pr_line="#${PR_NUM[$branch]} MERGED"
    fi
  elif [[ -n "${MERGED_SET[$branch]+x}" ]]; then
    tier=SAFE reason="merged (git ancestry)"
  elif [[ "${PR_STATE[$branch]:-}" == "CLOSED" ]]; then
    tier=REVIEW reason="PR closed without merge" pr_line="#${PR_NUM[$branch]} CLOSED"
  elif [[ -n "${GONE_SET[$branch]+x}" ]]; then
    if [[ -z "$ahead_default" ]]; then
      tier=REVIEW reason="upstream gone, cannot compare against origin/${DEFAULT_BRANCH}"
    elif [[ "$ahead_default" -gt 0 ]]; then
      tier=REVIEW reason="upstream gone, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
    else
      tier=LIKELY-SAFE reason="upstream gone"
    fi
  elif [[ "$no_upstream" == 1 && -n "$ahead_default" && "$ahead_default" -gt 0 ]]; then
    tier=REVIEW reason="no upstream, ${ahead_default} commits not on origin/${DEFAULT_BRANCH}"
  elif [[ "$age_days" -gt "$CLEAN_STALE_BRANCH_DAYS" ]]; then
    tier=REVIEW reason="stale (${age_days}d)"
  else
    tier=REVIEW reason="orphaned or needs review"
  fi

  if [[ "$tier" == REVIEW && $ORIGIN_DEFAULT -eq 1 && -n "$local_tip" && -n "$ahead_default" ]]; then
    case "${PR_STATE[$branch]:-}" in
    MERGED | CLOSED | OPEN) ;;
    *)
      if landed_reason="$(landed_proof "$branch")"; then
        tier=LIKELY-SAFE reason="$landed_reason"
      fi
      ;;
    esac
  fi

  if [[ -n "$OP_PATH" && ("$tier" == SAFE || "$tier" == LIKELY-SAFE) ]]; then
    tier=REVIEW reason="operation in progress: $OP_PATH" landed_reason=""
  fi

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
  printf 'Family: %s\n' "$(branch_family "$branch")"
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

if [[ $READ_ONLY -eq 0 && -z "$CAPTURE_ERROR" ]]; then
  written="$(awk -F'\t' -v at="$CAPTURED_AT" \
    'NF == 10 && $2 ~ /^[0-9a-f]+$/ && length($2) >= 40 && $10 == at { n++ } END { print n + 0 }' \
    "$CAPTURE_TMP" 2>/dev/null | tr -d '\r')"
  if [[ "${written:-x}" != "$CAPTURE_ROWS" ]]; then
    CAPTURE_ERROR="short write: expected $CAPTURE_ROWS rows, found ${written:-0} in $CAPTURE_TMP"
  elif ! mv -f "$CAPTURE_TMP" "$CAPTURE_PATH" 2>/dev/null; then
    CAPTURE_ERROR="cannot rename $CAPTURE_TMP into place"
  fi
fi
if [[ $READ_ONLY -eq 1 ]]; then
  printf 'TipCaptureSkipped: --read-only, no capture was written; git-branch-delete.sh refuses without one, so re-run without --read-only before deleting\n'
elif [[ -n "$CAPTURE_ERROR" ]]; then
  [[ $CAPTURE_TMP_OWNED -eq 1 ]] && rm -f "$CAPTURE_TMP" 2>/dev/null
  printf 'TipCaptureError: %s\n' "$CAPTURE_ERROR"
else
  printf 'TipCapture: %s\n' "$CAPTURE_PATH"
fi

printf 'Summary: protected=%s worktree=%s safe=%s likely-safe=%s lossy=%s review=%s\n' "$prot" "$wt" "$safe" "$likely" "$lossy" "$review"
exit 0
