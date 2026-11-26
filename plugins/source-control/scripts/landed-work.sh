#!/usr/bin/env bash
# Exit codes:
#   0  success — every target classified
#   2  usage error
#   3  no target resolved (no worktree found for the given scope)
#   4  environment error — git absent, or the scope is not a git repository
#   5  row-count assertion failed — the emitted rows do not match the worktree
#      list the run was supposed to cover. A truncated pass must fail loudly; a
#      short list read as "nothing at risk" is the failure mode this guards.

set -uo pipefail

LANDED_DIR="${BASH_SOURCE[0]%/*}"
[[ "$LANDED_DIR" == "${BASH_SOURCE[0]}" ]] && LANDED_DIR=.
# shellcheck source=lib/worktree-facts.sh
source "$LANDED_DIR/lib/worktree-facts.sh" || { echo "error: cannot load lib/worktree-facts.sh" >&2; exit 4; }

PROG=${0##*/}

usage() {
  cat >&2 <<EOF
$PROG — read-only landed-vs-stranded classification for git worktrees.

Usage:
  $PROG [--repo-dir <dir>] [--worktree <path>]... [--base <ref>]
        [--merged-refs-file <path>] [--no-peers] [--merged-pr-proof]
        [--merged-pr-limit <n>]
  $PROG --path-key <value>
  $PROG --help

Options:
  --repo-dir <dir>    Repository whose worktrees are classified. Default: the
                      current directory. Ignored when --worktree is given.
  --worktree <path>   Classify exactly this path instead of enumerating.
                      Repeatable. A path that is not a work-tree ROOT is
                      reported as notgit rather than silently inheriting the
                      containing repository's state.
  --base <ref>        Base to test landedness against. Default: origin/HEAD,
                      then origin/main, then origin/master. No base resolves
                      to landed=? — never to no.
  --merged-refs-file <path>
                      Newline-separated branch names whose pull request is
                      MERGED. A landed=no worktree whose branch appears here is
                      reported as superseded: the base probably holds a later
                      revision of the same change. NAME evidence only — a name
                      reused after that merge matches too, so superseded is a
                      narrowed reading of a landed=no row, never a safe one.
                      Collected by the caller (gh), so this script stays
                      offline.
  --no-peers          Skip peer detection (another worktree holding the same
                      commits). Peer detection is O(n^2) ancestry probes.
  --merged-pr-proof   For a row that is not landed, find the branch's merged pull
                      request and report landed when local HEAD equals or is an
                      ancestor of the PR head commit, or every unpushed local
                      commit is in the PR's commit list. The PRs come from one
                      paged GraphQL listing (\`gh api\`) of merged PRs per
                      repository and base, read once and reused for every
                      worktree (the only network use). The number of gh calls
                      the run made, one per page, is printed on stderr. A
                      failed read keeps the prior verdict
                      and names the read in the reason. Off by default, so the
                      script stays offline.
  --merged-pr-limit <n>
                      Most merged PRs that listing reads, most recently updated
                      first, 100 per page.
                      Default: 1000. A branch whose PR is older than that window
                      stays unproven, and its reason says the listing was full.
  --path-key <value>  Print the path comparison key for <value> and exit. A
                      debug seam the test suite asserts the normalizer through.

Columns:
  path branch head unpushed landed method base inprogress staged unstaged
  conflicted untracked peers risk reason
EOF
}

die() {
  printf '%s: %s\n' "$PROG" "$1" >&2
  exit "${2:-2}"
}

CASE_INSENSITIVE_PATHS=false
WINDOWS_PATHS=false
case "$(uname -s 2>/dev/null || true)" in
MINGW* | MSYS* | CYGWIN*)
  CASE_INSENSITIVE_PATHS=true
  WINDOWS_PATHS=true
  ;;
*) ;;
esac

path_key() {
  local value="${1//\\//}"
  if [[ "$WINDOWS_PATHS" == "true" ]]; then
    case "$value" in
    /?/*) value="${value:1:1}:${value:2}" ;;
    /?) value="${value:1:1}:" ;;
    *) ;;
    esac
  fi
  while [[ "$value" == */ ]]; do value="${value%/}"; done
  if [[ "$CASE_INSENSITIVE_PATHS" == "true" ]]; then
    printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
  else
    printf '%s' "$value"
  fi
}

REPO_DIR="."
BASE_REF=""
MERGED_REFS_FILE=""
DO_PEERS=true
USE_PR_PROOF=false
MERGED_PR_LIMIT=1000
EXPLICIT_TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --path-key)
    [[ $# -ge 2 ]] || die "--path-key requires a value"
    path_key "$2"
    printf '\n'
    exit 0
    ;;
  --repo-dir)
    [[ $# -ge 2 ]] || die "--repo-dir requires a value"
    REPO_DIR="$2"
    shift 2
    ;;
  --worktree)
    [[ $# -ge 2 ]] || die "--worktree requires a value"
    EXPLICIT_TARGETS+=("$2")
    shift 2
    ;;
  --base)
    [[ $# -ge 2 ]] || die "--base requires a value"
    BASE_REF="$2"
    shift 2
    ;;
  --merged-refs-file)
    [[ $# -ge 2 ]] || die "--merged-refs-file requires a value"
    MERGED_REFS_FILE="$2"
    shift 2
    ;;
  --no-peers)
    DO_PEERS=false
    shift
    ;;
  --merged-pr-proof)
    USE_PR_PROOF=true
    shift
    ;;
  --merged-pr-limit)
    [[ $# -ge 2 ]] || die "--merged-pr-limit requires a value"
    [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "--merged-pr-limit must be a positive integer: $2"
    MERGED_PR_LIMIT="$2"
    shift 2
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git not found on PATH" 4

if [[ -n "$MERGED_REFS_FILE" && ! -f "$MERGED_REFS_FILE" ]]; then
  die "--merged-refs-file not found: $MERGED_REFS_FILE"
fi

is_worktree_root() {
  local prefix
  prefix=$(git -C "$1" rev-parse --show-prefix 2>/dev/null) || return 1
  [[ -z "$prefix" ]]
}

inprogress_of() {
  local p="$1" name resolved pair
  for name in rebase-merge rebase-apply; do
    resolved=$(git -C "$p" rev-parse --git-path "$name" 2>/dev/null) || continue
    if [[ -d "$resolved" ]]; then
      printf 'rebase'
      return 0
    fi
  done
  for pair in MERGE_HEAD:merge CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert BISECT_LOG:bisect; do
    resolved=$(git -C "$p" rev-parse --git-path "${pair%%:*}" 2>/dev/null) || continue
    if [[ -e "$resolved" ]]; then
      printf '%s' "${pair#*:}"
      return 0
    fi
  done
  printf 'none'
}

S_STAGED=0
S_UNSTAGED=0
S_CONFLICTED=0
S_UNTRACKED=0

status_counts() {
  local p="$1" line x y status_out="$WORKDIR/status.$$"
  S_STAGED=0
  S_UNSTAGED=0
  S_CONFLICTED=0
  S_UNTRACKED=0
  if ! git -C "$p" status --porcelain >"$status_out" 2>/dev/null; then
    rm -f "$status_out"
    return 1
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    x="${line:0:1}"
    y="${line:1:1}"
    case "$x$y" in
    '??')
      S_UNTRACKED=$((S_UNTRACKED + 1))
      continue
      ;;
    '!!') continue ;;
    DD | AU | UD | UA | DU | AA | UU)
      S_CONFLICTED=$((S_CONFLICTED + 1))
      continue
      ;;
    *) ;;
    esac
    [[ "$x" != " " ]] && S_STAGED=$((S_STAGED + 1))
    [[ "$y" != " " ]] && S_UNSTAGED=$((S_UNSTAGED + 1))
  done <"$status_out"
  rm -f "$status_out"
  return 0
}

resolve_base() {
  local p="$1" ref
  if [[ -n "$BASE_REF" ]]; then
    printf '%s' "$BASE_REF"
    return 0
  fi
  if ref=$(git -C "$p" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s' "${ref#refs/remotes/}"
    return 0
  fi
  for ref in origin/main origin/master; do
    if git -C "$p" rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1; then
      printf '%s' "$ref"
      return 0
    fi
  done
  return 1
}

patch_ids() {
  local p="$1" range="$2" out="$3" patches="$WORKDIR/patches.$$" pairs="$WORKDIR/pairs.$$" rc=0
  : >"$out"
  git -C "$p" log -p --no-merges --no-color "$range" >"$patches" 2>/dev/null || rc=1
  if ((rc == 0)) && [[ -s "$patches" ]]; then
    git patch-id --verbatim <"$patches" >"$pairs" || rc=1
    cut -d' ' -f1 "$pairs" | sort >"$out"
  fi
  rm -f "$patches" "$pairs"
  return "$rc"
}

extend_base_window() {
  local p="$1" needed="$2" seen="$WORKDIR/base-window.seen" pairs="$WORKDIR/base-window.pairs"
  local missing="$WORKDIR/base-window.missing" patches="$WORKDIR/base-window.patches"
  local new="$WORKDIR/base-window.new" rc=0
  [[ -f "$seen" ]] || : >"$seen"
  [[ -f "$pairs" ]] || : >"$pairs"
  : >"$new"
  comm -23 "$needed" "$seen" >"$missing" 2>/dev/null || rc=1
  if ((rc == 0)) && [[ -s "$missing" ]]; then
    git -C "$p" log -p --no-merges --no-color --no-walk --stdin <"$missing" >"$patches" 2>/dev/null || rc=1
    if ((rc == 0)) && [[ -s "$patches" ]]; then
      git patch-id --verbatim <"$patches" >"$new" || rc=1
    fi
    if ((rc == 0)); then
      { sort -m "$seen" "$missing" >"$seen.next" && mv "$seen.next" "$seen" && cat "$new" >>"$pairs"; } || rc=1
    fi
  fi
  rm -f "$missing" "$patches" "$new" "$seen.next"
  return "$rc"
}

only_empty_commits_unhashed() {
  local p="$1" range="$2" hashed="$3" all="$WORKDIR/range-commits.$$" c rc=0
  git -C "$p" rev-list --no-merges "$range" 2>/dev/null | sort >"$all" || rc=1
  if ((rc == 0)); then
    while read -r c; do
      git -C "$p" diff-tree --quiet --root --no-commit-id -r "$c" 2>/dev/null || { rc=1; break; }
    done < <(comm -23 "$all" "$hashed")
  fi
  rm -f "$all"
  return "$rc"
}

L_STATE="?"
L_METHOD="none"
L_BASE=""
L_REASON=""

classify_landed() {
  local p="$1" base base_sha mb range_id branch_expected branch_count
  local base_ids branch_ids touched
  L_STATE="?"
  L_METHOD="none"
  L_BASE=""
  L_REASON=""

  if ! base=$(resolve_base "$p"); then
    L_REASON="no-base-ref"
    return 0
  fi
  local base_err="$WORKDIR/base-resolve.err"
  if ! base_sha=$(git -C "$p" rev-parse --verify "$base^{commit}" 2>"$base_err"); then
    L_REASON="base-unresolvable:$base"
    return 0
  fi
  if [[ -s "$base_err" ]] && grep -qi 'ambiguous' "$base_err"; then
    L_REASON="base-ref-ambiguous:$base"
    return 0
  fi
  L_BASE="$base@${base_sha:0:12}"
  local mb_count
  mb=$(git -C "$p" merge-base --all "$base_sha" HEAD 2>/dev/null) || mb=""
  if [[ -z "$mb" ]]; then
    L_REASON="no-merge-base"
    return 0
  fi
  mb_count=$(printf '%s\n' "$mb" | grep -c .)
  if [[ "$mb_count" -ne 1 ]]; then
    L_REASON="ambiguous-merge-base-$mb_count-candidates"
    return 0
  fi

  local base_commits="$WORKDIR/base.range" base_pairs="$WORKDIR/base.pairs" base_expected base_count
  base_ids="$WORKDIR/base.ids"
  if ! git -C "$p" rev-list --no-merges "$mb..$base_sha" >"$base_commits.raw" 2>/dev/null ||
    ! sort "$base_commits.raw" >"$base_commits"; then
    L_REASON="base-range-unreadable"
    return 0
  fi
  base_expected=$(wc -l <"$base_commits" | tr -d '[:space:]')
  if ! extend_base_window "$p" "$base_commits" ||
    ! awk 'FILENAME == ARGV[1] { want[$1] = 1; next } ($2 in want)' \
      "$base_commits" "$WORKDIR/base-window.pairs" >"$base_pairs"; then
    L_REASON="base-patchid-failed"
    return 0
  fi
  cut -d' ' -f1 "$base_pairs" | sort >"$base_ids"
  cut -d' ' -f2 "$base_pairs" | sort >"$base_ids.commits"
  base_count=$(wc -l <"$base_ids" | tr -d '[:space:]')
  if [[ "$base_count" -ne "$base_expected" ]] &&
    ! only_empty_commits_unhashed "$p" "$mb..$base_sha" "$base_ids.commits"; then
    L_REASON="base-patchid-incomplete-$base_count-of-$base_expected-commits"
    return 0
  fi

  branch_ids="$WORKDIR/branch.ids"
  branch_expected=$(git -C "$p" rev-list --count --no-merges "$mb..HEAD" 2>/dev/null) || branch_expected=""
  if [[ -z "$branch_expected" ]]; then
    L_REASON="branch-range-unreadable"
    return 0
  fi
  if ! patch_ids "$p" "$mb..HEAD" "$branch_ids"; then
    L_REASON="branch-patchid-failed"
    return 0
  fi
  branch_count=$(wc -l <"$branch_ids" | tr -d '[:space:]')
  if [[ "$branch_count" -ne "$branch_expected" ]]; then
    L_REASON="patchid-set-incomplete-$branch_count-of-$branch_expected-commits"
    return 0
  fi

  if git -C "$p" diff "$mb..HEAD" >"$WORKDIR/rangediff" 2>/dev/null && [[ -s "$WORKDIR/rangediff" ]]; then
    range_id=$(git patch-id --verbatim <"$WORKDIR/rangediff" | cut -d' ' -f1)
    if [[ -n "$range_id" ]] && grep -Fxq "$range_id" "$base_ids"; then
      L_STATE="yes"
      L_METHOD="range-patchid"
      return 0
    fi
  fi

  if [[ "$branch_expected" -gt 0 ]]; then
    local unmatched="$WORKDIR/branch-not-on-base"
    if comm -23 "$branch_ids" "$base_ids" >"$unmatched" 2>/dev/null; then
      if [[ ! -s "$unmatched" ]]; then
        L_STATE="yes"
        L_METHOD="per-commit-patchid"
        return 0
      fi
    else
      L_REASON="patchid-set-comparison-failed"
      return 0
    fi
  fi

  touched="$WORKDIR/touched"
  if ! git -C "$p" diff --name-only --no-renames -z "$mb..HEAD" >"$touched" 2>/dev/null; then
    L_REASON="touched-paths-unreadable"
    return 0
  fi
  if [[ ! -s "$touched" ]]; then
    L_REASON="branch-adds-no-content"
    return 0
  fi

  local -a specs=()
  local pth
  while IFS= read -r -d '' pth; do specs+=(":(literal)$pth"); done <"$touched"
  if [[ ${#specs[@]} -eq 0 ]]; then
    L_REASON="touched-paths-unparsable"
    return 0
  fi

  local i rc differs=0
  local -a chunk=()
  for ((i = 0; i < ${#specs[@]}; i += 200)); do
    chunk=("${specs[@]:i:200}")
    git -C "$p" diff --quiet --no-renames "$base_sha..HEAD" -- "${chunk[@]}" 2>/dev/null
    rc=$?
    if [[ "$rc" -eq 1 ]]; then
      differs=1
      break
    fi
    if [[ "$rc" -ne 0 ]]; then
      L_REASON="two-dot-unreadable"
      return 0
    fi
  done
  if [[ "$differs" -eq 0 ]]; then
    L_STATE="yes"
    L_METHOD="two-dot-empty"
    return 0
  fi
  L_STATE="no"
  L_METHOD="two-dot"
  L_REASON="head-differs-from-base-on-${#specs[@]}-touched-path(s)"
}

GH_CALLS=0
MP_KEYS=()
MP_ERRS=()
MP_FILE=""
MP_ERR=""

# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
MERGED_PR_QUERY='query($owner: String!, $name: String!, $base: String!, $first: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(states: MERGED, baseRefName: $base, first: $first, after: $after,
      orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes { headRefName headRefOid baseRefName commits(first: 100) { nodes { commit { oid } } } }
    }
  }
}'
MERGED_PR_JQ='.data.repository.pullRequests
  | (.nodes[] | "pr " + .headRefName + " " + .baseRefName, "head " + .headRefOid,
      (.commits.nodes[] | "commit " + .commit.oid)),
    "page " + (.pageInfo.hasNextPage | tostring) + " " + (.pageInfo.endCursor // "")'

merged_pr_listing() {
  local p="$1" base_name="$2" repo key i err page got=0 n first more cursor
  local -a after=()
  MP_FILE=""
  MP_ERR=""
  repo=$(cd "$p" 2>/dev/null && common=$(git rev-parse --git-common-dir 2>/dev/null) &&
    CDPATH='' cd -- "$common" 2>/dev/null && pwd -P) || repo=""
  key="${repo:-$p}|$base_name"
  for ((i = 0; i < ${#MP_KEYS[@]}; i++)); do
    if [[ "${MP_KEYS[$i]}" == "$key" ]]; then
      MP_FILE="$WORKDIR/merged-prs.$i"
      MP_ERR="${MP_ERRS[$i]}"
      [[ -z "$MP_ERR" ]]
      return
    fi
  done
  i=${#MP_KEYS[@]}
  MP_FILE="$WORKDIR/merged-prs.$i"
  page="$MP_FILE.page"
  : >"$MP_FILE"
  while :; do
    first=$((MERGED_PR_LIMIT - got))
    ((first > 100)) && first=100
    GH_CALLS=$((GH_CALLS + 1))
    if ! (cd "$p" && gh api graphql -f query="$MERGED_PR_QUERY" -F owner='{owner}' -F name='{repo}' \
      -f base="$base_name" -F first="$first" ${after[@]+"${after[@]}"} --jq "$MERGED_PR_JQ") >"$page" 2>"$MP_FILE.err"; then
      err=$(head -n 1 "$MP_FILE.err" | tr '\t;' '  ' | cut -c1-120)
      MP_ERR="gh-pr-list${err:+ ($err)}"
      : >"$MP_FILE"
      break
    fi
    grep -v '^page ' "$page" >>"$MP_FILE"
    n=$(grep -c '^pr ' "$page")
    got=$((got + n))
    more=$(sed -n 's/^page //p' "$page")
    cursor="${more#* }"
    [[ "${more%% *}" == "true" && -n "$cursor" && "$n" -gt 0 && "$got" -lt "$MERGED_PR_LIMIT" ]] || break
    after=(-f after="$cursor")
  done
  MP_KEYS+=("$key")
  MP_ERRS+=("$MP_ERR")
  [[ -z "$MP_ERR" ]]
}

add_reason() { L_REASON="${L_REASON:+$L_REASON; }$1"; }

merged_pr_proof() {
  local p="$1" branch="$2" out="$WORKDIR/merged-pr.out" head_oid unpushed_list sha
  local -a pr_heads=()
  local commits_file="$WORKDIR/merged-pr.commits" kind val
  : >"$commits_file"
  if ! command -v gh >/dev/null 2>&1; then
    add_reason "merged-pr-read-failed:gh-not-found"
    return 1
  fi
  local base_name="${L_BASE%@*}"
  base_name="${base_name#*/}"
  if [[ -z "$L_BASE" || -z "$base_name" ]]; then
    add_reason "merged-pr-read-failed:no-resolved-base"
    return 1
  fi
  if ! merged_pr_listing "$p" "$base_name"; then
    add_reason "merged-pr-read-failed:$MP_ERR"
    return 1
  fi
  if ! awk -v b="$branch" '$1 == "pr" { keep = ($2 "" == b ""); if (keep) print "pr " $3; next } keep' \
    "$MP_FILE" >"$out"; then
    add_reason "merged-pr-read-failed:branch-filter"
    return 1
  fi
  local in_base=false
  while read -r kind val; do
    case "$kind" in
    pr)
      in_base=false
      if [[ "$val" == "$base_name" ]]; then in_base=true; fi
      ;;
    head) [[ "$in_base" == "true" ]] && pr_heads+=("$val") ;;
    commit) [[ "$in_base" == "true" ]] && printf '%s\n' "$val" >>"$commits_file" ;;
    *) ;;
    esac
  done <"$out"
  if [[ ${#pr_heads[@]} -eq 0 ]]; then
    local window=""
    if [[ "$(grep -c '^pr ' "$MP_FILE")" -ge "$MERGED_PR_LIMIT" ]]; then
      window="-in-newest-$MERGED_PR_LIMIT"
    fi
    add_reason "no-merged-pr-into-$base_name-for-branch$window"
    return 1
  fi

  for head_oid in "${pr_heads[@]}"; do
    if git -C "$p" merge-base --is-ancestor HEAD "$head_oid" 2>/dev/null; then
      L_STATE="yes"
      L_METHOD="merged-pr-head"
      L_REASON="head-is-ancestor-of-merged-pr-head"
      return 0
    fi
  done

  if ! unpushed_list=$(git -C "$p" rev-list HEAD --not --remotes 2>/dev/null) || [[ -z "$unpushed_list" ]]; then
    add_reason "merged-pr-read-failed:local-commit-list"
    return 1
  fi
  while read -r sha; do
    [[ -z "$sha" ]] && continue
    if ! grep -Fxq "$sha" "$commits_file"; then
      add_reason "local-commits-not-all-in-merged-pr"
      return 1
    fi
  done <<<"$unpushed_list"
  L_STATE="yes"
  L_METHOD="merged-pr-commits"
  L_REASON="every-unpushed-commit-in-merged-pr"
  return 0
}

WORKDIR=""
cleanup() { [[ -n "$WORKDIR" ]] && rm -rf "$WORKDIR"; }

T_PATH=()
T_BRANCH=()
T_HEAD=()

collect_targets() {
  local path
  if [[ ${#EXPLICIT_TARGETS[@]} -gt 0 ]]; then
    for path in "${EXPLICIT_TARGETS[@]}"; do
      T_PATH+=("$path")
      T_BRANCH+=("")
      T_HEAD+=("")
    done
    return 0
  fi
  git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 ||
    die "not a git repository: $REPO_DIR" 4

  local porcelain="$WORKDIR/worktree-list"
  if ! git -C "$REPO_DIR" worktree list --porcelain -z >"$porcelain" 2>/dev/null; then
    die "git worktree list failed in $REPO_DIR ($(worktree_list_z_floor_note)) — refusing to report a partial inventory" 4
  fi

  worktree_facts_parse_z "$porcelain"
  local i
  if [[ ${#WT_FACT_PATH[@]} -gt 0 ]]; then
    for i in "${!WT_FACT_PATH[@]}"; do
      T_PATH+=("${WT_FACT_PATH[$i]}")
      T_BRANCH+=("${WT_FACT_BRANCH[$i]}")
      T_HEAD+=("${WT_FACT_HEAD[$i]}")
    done
  fi
}

assert_row_count() {
  local expected="$1" actual="$2"
  if [[ "$expected" -ne "$actual" ]]; then
    printf '%s: row-count assertion failed — enumerated %s worktree(s), emitted %s row(s)\n' \
      "$PROG" "$expected" "$actual" >&2
    return 5
  fi
  return 0
}

[[ -n "${LANDED_WORK_LIB:-}" ]] && return 0

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/landed-work.XXXXXX") || die "cannot create work directory" 4
trap cleanup EXIT

collect_targets
[[ ${#T_PATH[@]} -gt 0 ]] || die "no worktree found for the given scope" 3

R_UNPUSHED=()
R_LANDED=()
R_METHOD=()
R_BASE=()
R_INPROGRESS=()
R_STAGED=()
R_UNSTAGED=()
R_CONFLICTED=()
R_UNTRACKED=()
R_REASON=()
R_NOTGIT=()
R_BARE=()

merged_ref() {
  local name="$1"
  [[ -n "$MERGED_REFS_FILE" && -n "$name" && "$name" != "(detached)" ]] || return 1
  grep -Fxq "$name" "$MERGED_REFS_FILE"
}

push_counts() {
  R_STAGED+=("$1")
  R_UNSTAGED+=("$2")
  R_CONFLICTED+=("$3")
  R_UNTRACKED+=("$4")
}

push_unprobed_row() {
  R_NOTGIT+=("$1")
  R_BARE+=("$2")
  R_UNPUSHED+=("$3")
  R_LANDED+=("$3")
  R_METHOD+=("none")
  R_BASE+=("")
  R_INPROGRESS+=("$4")
  push_counts "$5" "$5" "$5" "$5"
  R_REASON+=("$6")
}

for ((idx = 0; idx < ${#T_PATH[@]}; idx++)); do
  p="${T_PATH[$idx]}"
  reason=""
  if [[ ! -d "$p" ]]; then
    reason="path-absent"
  elif ! is_worktree_root "$p"; then
    reason="not-a-worktree-root; probing it with git -C reports the containing repository"
  fi
  if [[ -n "$reason" ]]; then
    push_unprobed_row yes no "?" "?" "?" "$reason"
    continue
  fi

  if [[ "$(git -C "$p" rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
    push_unprobed_row no yes "n/a" none 0 "bare-repository; holds no working tree to strand"
    T_BRANCH[idx]="(bare)"
    continue
  fi
  R_NOTGIT+=("no")
  R_BARE+=("no")

  unpushed=$(git -C "$p" rev-list --count HEAD --not --remotes 2>/dev/null) || unpushed=""
  unpushed="${unpushed:-?}"
  R_UNPUSHED+=("$unpushed")

  if [[ -z "${T_HEAD[$idx]}" ]]; then
    T_HEAD[idx]=$(git -C "$p" rev-parse HEAD 2>/dev/null || printf '')
  fi
  if [[ -z "${T_BRANCH[$idx]}" ]]; then
    if branch_name=$(git -C "$p" symbolic-ref --quiet --short HEAD 2>/dev/null); then
      T_BRANCH[idx]="$branch_name"
    else
      T_BRANCH[idx]="(detached)"
    fi
  fi

  if [[ "$unpushed" == "0" ]]; then
    R_LANDED+=("n/a")
    R_METHOD+=("none")
    R_BASE+=("")
    reason="nothing-unpushed"
  else
    classify_landed "$p"
    if [[ "$USE_PR_PROOF" == "true" && "$L_STATE" != "yes" && "${T_BRANCH[$idx]}" != "(detached)" ]]; then
      merged_pr_proof "$p" "${T_BRANCH[$idx]}" || true
    fi
    R_LANDED+=("$L_STATE")
    R_METHOD+=("$L_METHOD")
    R_BASE+=("$L_BASE")
    reason="$L_REASON"
  fi

  inprog=$(inprogress_of "$p")
  R_INPROGRESS+=("$inprog")
  if status_counts "$p"; then
    push_counts "$S_STAGED" "$S_UNSTAGED" "$S_CONFLICTED" "$S_UNTRACKED"
  else
    push_counts "?" "?" "?" "?"
    reason="${reason:+$reason; }status-unreadable: the working tree was not inspected"
  fi
  if [[ "$inprog" != "none" ]]; then
    reason="${reason:+$reason; }$inprog-in-progress: the operation's transient state (staged result recomputable from base, sequencer position) dies with the directory"
  fi
  R_REASON+=("$reason")
done

if [[ "$USE_PR_PROOF" == "true" ]]; then
  printf '%s: merged-pr-proof made %s gh call(s)\n' "$PROG" "$GH_CALLS" >&2
fi

assert_row_count "${#T_PATH[@]}" "${#R_LANDED[@]}" || exit 5

PEERS=()
for ((idx = 0; idx < ${#T_PATH[@]}; idx++)); do
  PEERS+=("")
done
if [[ "$DO_PEERS" == "true" && ${#T_PATH[@]} -le 50 ]]; then
  for ((idx = 0; idx < ${#T_PATH[@]}; idx++)); do
    if [[ "${R_NOTGIT[$idx]}" == "yes" || -z "${T_HEAD[$idx]}" ]]; then
      continue
    fi
    for ((jdx = 0; jdx < ${#T_PATH[@]}; jdx++)); do
      if [[ $jdx -eq $idx || "${R_NOTGIT[$jdx]}" == "yes" || -z "${T_HEAD[$jdx]}" ]]; then
        continue
      fi
      if [[ "${T_HEAD[$idx]}" == "${T_HEAD[$jdx]}" ]] ||
        git -C "${T_PATH[$idx]}" merge-base --is-ancestor "${T_HEAD[$idx]}" "${T_HEAD[$jdx]}" 2>/dev/null; then
        PEERS[idx]="${PEERS[$idx]:+${PEERS[$idx]},}${T_PATH[$jdx]}"
      fi
    done
  done
elif [[ "$DO_PEERS" == "true" ]]; then
  printf '%s: peer detection skipped — %s worktrees exceeds the 50-target ancestry budget\n' \
    "$PROG" "${#T_PATH[@]}" >&2
fi

printf 'path\tbranch\thead\tunpushed\tlanded\tmethod\tbase\tinprogress\tstaged\tunstaged\tconflicted\tuntracked\tpeers\trisk\treason\n'

emitted=0
for ((idx = 0; idx < ${#T_PATH[@]}; idx++)); do
  reason="${R_REASON[$idx]}"
  if [[ "${R_NOTGIT[$idx]}" == "yes" ]]; then
    risk="notgit"
  elif [[ "${R_BARE[$idx]}" == "yes" ]]; then
    risk="bare"
  elif [[ "${R_LANDED[$idx]}" == "no" ]] && merged_ref "${T_BRANCH[$idx]}"; then
    risk="superseded"
  elif [[ "${R_LANDED[$idx]}" == "no" ]]; then
    risk="STRANDED"
  elif [[ "${R_LANDED[$idx]}" == "?" ]]; then
    risk="UNKNOWN"
  elif [[ "${R_INPROGRESS[$idx]}" != "none" ]]; then
    risk="in-progress"
  elif [[ "${R_LANDED[$idx]}" == "yes" ]]; then
    risk="landed"
  elif [[ "${R_CONFLICTED[$idx]}" != "0" || "${R_UNSTAGED[$idx]}" != "0" || "${R_STAGED[$idx]}" != "0" ]]; then
    risk="dirty"
  else
    risk="ok"
  fi
  head_col="${T_HEAD[$idx]:0:12}"
  worktree_fact_row \
    "${T_PATH[$idx]}" "${T_BRANCH[$idx]}" "$head_col" "${R_UNPUSHED[$idx]}" \
    "${R_LANDED[$idx]}" "${R_METHOD[$idx]}" "${R_BASE[$idx]}" "${R_INPROGRESS[$idx]}" \
    "${R_STAGED[$idx]}" "${R_UNSTAGED[$idx]}" "${R_CONFLICTED[$idx]}" "${R_UNTRACKED[$idx]}" \
    "${PEERS[$idx]}" "$risk" "$reason"
  emitted=$((emitted + 1))
done

assert_row_count "${#T_PATH[@]}" "$emitted" || exit 5
exit 0
