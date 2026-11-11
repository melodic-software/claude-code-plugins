#!/usr/bin/env bash
# Reads the signals branch-update-method.sh decides from, for one pull request
# or one branch, and prints them as one JSON object. Run it from the checkout.
#
#   branch-update-signals.sh --pr <n> [--repo <owner/repo>] [flags]
#   branch-update-signals.sh --branch <b> --base <b> [--repo <owner/repo>] [flags]
#
#   --allow-rewrite       a pushed head may be rewritten; only attended create,
#                         ready and reassess --act pass it
#   --base-fixed-failure  the caller knows a failure on the head was fixed on
#                         the base, so base_change_needed is yes
#
# The overlap read diffs HEAD against the base, so it runs only when HEAD is the
# head being asked about; otherwise overlap is unknown.
#
# A read that fails is `unknown` (`blocked` for rewrite, `auto` for the setting,
# the literal `unknown` for head_sha). GitHub facts behind each read:
# ../reference/providers/github/branch-update-signals.md
#
# Exit: 0 signals printed, whatever failed to read; 2 usage error or jq missing.
set -uo pipefail

# portability-scope: every signal reads the pull request, its repository or its rules through gh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAP="$SCRIPT_DIR/stale-base-overlap.sh"
RESOLVER="$SCRIPT_DIR/../skills/pull-request/scripts/resolve-remote.sh"
# shellcheck source=../lib/base-file.sh
source "$SCRIPT_DIR/../lib/base-file.sh"
# shellcheck source=../lib/github-remote.sh
source "$SCRIPT_DIR/../lib/github-remote.sh"
readonly DEPENDENCY_MANAGERS='dependabot dependabot-preview renovate renovate-bot'
# The login normalization babysit_classify.py applies to a dependency manager.
readonly NORM='def norm: ascii_downcase | sub("^app/"; "") | sub("\\[bot\\]$"; "");'

usage() {
  echo "usage: branch-update-signals.sh (--pr <n> | --branch <b> --base <b>) [--repo <owner/repo>] [--allow-rewrite] [--base-fixed-failure]" >&2
  exit 2
}

PR="" BRANCH="" BASE="" REPO="" ALLOW_REWRITE=0 BASE_FIXED=0
while (($#)); do
  case "$1" in
    --pr | --branch | --base | --repo)
      (($# >= 2)) && [[ -n "$2" ]] || usage
      case "$1" in
        --pr) PR="$2" ;;
        --branch) BRANCH="$2" ;;
        --base) BASE="$2" ;;
        *) REPO="$2" ;;
      esac
      shift
      ;;
    --allow-rewrite) ALLOW_REWRITE=1 ;;
    --base-fixed-failure) BASE_FIXED=1 ;;
    *) usage ;;
  esac
  shift
done
if [[ -n "$PR" ]]; then
  [[ "$PR" =~ ^[0-9]+$ && -z "$BRANCH" && -z "$BASE" ]] || usage
else
  [[ -n "$BRANCH" && -n "$BASE" ]] || usage
fi
[[ -z "$REPO" || "$REPO" =~ ^[A-Za-z0-9._][A-Za-z0-9._-]*/[A-Za-z0-9._][A-Za-z0-9._-]*$ ]] || usage
command -v jq >/dev/null 2>&1 || {
  echo "branch-update-signals.sh: jq not found on PATH" >&2
  exit 2
}

notice() { printf 'branch-update-signals: %s\n' "${1//[[:cntrl:]]/ }" >&2; }
uri() { jq -rn --arg v "$1" '$v | @uri'; }
# gh prints an error's JSON body on stdout, so a failed call answers nothing.
api() {
  local out
  out=$(gh api "$@" 2>/dev/null) || return 1
  tr -d '\r' <<<"$out"
}
paged() {
  local out
  out=$(gh api --paginate --slurp "$1" 2>/dev/null) || return 1
  tr -d '\r' <<<"$out" | jq -c 'add // []' 2>/dev/null
}
pull() { [[ -n "$PULL" ]] && jq -r "$1" <<<"$PULL" 2>/dev/null | tr -d '\r'; }
answer() { printf '%s\n' "${1:-unknown}"; }
# count_answer <n>: yes above zero, no at zero, unknown when <n> is not a count.
count_answer() {
  [[ "$1" =~ ^[0-9]+$ ]] || { answer ""; return; }
  if (($1 > 0)); then answer yes; else answer no; fi
}

load() {
  # gh api's placeholders follow GH_REPO; gh repo view with no argument ignores it.
  [[ -n "$REPO" ]] || REPO=$(api 'repos/{owner}/{repo}' --jq .full_name)
  if [[ -n "$PR" ]]; then
    PULL=$(api "repos/$REPO/pulls/$PR")
    COMMITS=$(paged "repos/$REPO/pulls/$PR/commits")
    HEAD_SHA=$(pull '.head.sha // empty')
    HEAD_REF=$(pull '.head.ref // empty')
    BASE=$(pull '.base.ref // empty')
  else
    HEAD_SHA=$(git rev-parse -q --verify "refs/heads/$BRANCH^{commit}" 2>/dev/null)
    HEAD_REF="$BRANCH"
  fi
  if [[ -n "$REPO" && -n "$BASE" ]]; then
    RULES=$(paged "repos/$REPO/rules/branches/$(uri "$BASE")")
    META=$(gh repo view "$REPO" --json defaultBranchRef,squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed 2>/dev/null | tr -d '\r')
    DEFAULT_BRANCH=$(jq -r '.defaultBranchRef.name // empty' <<<"$META" 2>/dev/null | tr -d '\r')
  fi
  CHECKOUT_HEAD=$(git rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)
  # A pull request's objects are only certain to be here when it is checked out.
  { [[ -z "$PR" ]] || [[ -n "$HEAD_SHA" && "$CHECKOUT_HEAD" == "$HEAD_SHA" ]]; } || return 0
  local remote
  remote=$(remote_of_repo "$REPO")
  [[ -n "$remote" && -n "$BASE" ]] || return 0
  GIT_TERMINAL_PROMPT=0 git fetch --quiet --no-tags "$remote" "+refs/heads/$BASE:refs/remotes/$remote/$BASE" 2>/dev/null || return 0
  BASE_TIP=$(git rev-parse -q --verify "refs/remotes/$remote/$BASE^{commit}" 2>/dev/null)
}

history_ready() { [[ -n "$BASE_TIP" && -n "$HEAD_SHA" ]]; }

signal_behind() {
  local n=""
  if [[ -n "$PR" ]]; then
    [[ -n "$HEAD_SHA" && -n "$BASE" ]] && n=$(api "repos/$REPO/compare/$(uri "$BASE")...$HEAD_SHA" --jq .behind_by)
  else
    history_ready && n=$(git rev-list --count "$HEAD_SHA..$BASE_TIP" 2>/dev/null)
  fi
  count_answer "$n"
}

signal_conflict() {
  if [[ -n "$PR" ]]; then
    case "$(pull .mergeable)" in
      true) answer no ;;
      false) answer yes ;;
      *) answer "" ;;
    esac
    return
  fi
  history_ready || { answer ""; return; }
  git merge-tree --write-tree "$HEAD_SHA" "$BASE_TIP" >/dev/null 2>&1
  case $? in
    0) answer no ;;
    1) answer yes ;;
    *) answer "" ;;
  esac
}

signal_up_to_date_required() {
  if [[ -n "$PR" && "$(pull .mergeable_state)" == behind ]]; then
    answer yes
    return
  fi
  local ruleset classic=""
  ruleset=$(jq -r 'if any(.[]; .type == "required_status_checks"
      and .parameters.strict_required_status_checks_policy == true
      and ((.parameters.required_status_checks // []) | length > 0))
    then "yes" else "no" end' <<<"$RULES" 2>/dev/null)
  [[ "$ruleset" != yes ]] || { answer yes; return; }
  base_file_load --http-response < <(gh api -i "repos/$REPO/branches/$(uri "$BASE")/protection/required_status_checks" 2>/dev/null)
  case "$BASE_FILE_STATE" in
    absent) classic=no ;;
    ok) classic=$(jq -r 'if .strict == true then "yes" elif .strict == false then "no" else empty end' <<<"$BASE_FILE_DOC" 2>/dev/null) ;;
    *) ;;
  esac
  if [[ "$classic" == yes || ("$classic" == no && "$ruleset" == no) ]]; then
    answer "$classic"
  else
    answer ""
  fi
}

signal_native_stack() {
  if [[ -n "$PR" ]]; then
    answer "$(pull 'if (.stack | type) == "object" then "yes" else "no" end')"
    return
  fi
  local common file
  common=$(git rev-parse --git-common-dir 2>/dev/null) || { answer ""; return; }
  file="$common/gh-stack"
  [[ -f "$file" ]] || { answer no; return; }
  answer "$(jq -r --arg b "$BRANCH" 'if any(.stacks[]?.branches[]?; .branch == $b) then "yes" else "no" end' "$file" 2>/dev/null)"
}

signal_managed_head() {
  [[ -n "$PR" ]] || { answer no; return; }
  [[ -n "$PULL" ]] || { answer ""; return; }
  # shellcheck disable=SC2016 # False positive: each $name is a jq variable.
  answer "$(jq -r --arg managers "$DEPENDENCY_MANAGERS" "$NORM"'
    (.user.login | norm) as $l
    | if ($managers | split(" ") | index($l)) then "yes" else "no" end' <<<"$PULL" 2>/dev/null | tr -d '\r')"
}

# rewrite has no unknown: anything unread is blocked.
signal_rewrite() {
  if [[ -n "$PR" ]]; then
    local head_repo
    head_repo=$(pull '.head.repo.full_name // empty')
    [[ -n "$head_repo" && "${head_repo,,}" == "${REPO,,}" ]] || { echo blocked; return; }
  else
    local push_remote push_url url url_repo remote_heads
    push_remote=$(bash "$RESOLVER" --push "$BRANCH" 2>/dev/null) || { echo blocked; return; }
    push_url=$(git remote get-url --push --all "$push_remote" 2>/dev/null) || { echo blocked; return; }
    while IFS= read -r url; do
      url_repo=$(github_repo_of "$url")
      [[ -n "$url_repo" && "${url_repo,,}" == "${REPO,,}" ]] || { echo blocked; return; }
    done <<<"$push_url"
    remote_heads=$(GIT_TERMINAL_PROMPT=0 git ls-remote "$push_remote" "refs/heads/$BRANCH" 2>/dev/null) || { echo blocked; return; }
    [[ -n "$remote_heads" ]] || { echo allowed; return; }
  fi
  [[ "$ALLOW_REWRITE" == 1 && -n "$HEAD_REF" ]] || { echo blocked; return; }
  local rules verdict
  rules=$(paged "repos/$REPO/rules/branches/$(uri "$HEAD_REF")")
  [[ -n "$rules" ]] || { echo blocked; return; }
  verdict=$(jq -r 'if any(.[]; .type == "non_fast_forward") then "blocked" else "allowed" end' <<<"$rules" 2>/dev/null)
  printf '%s\n' "${verdict:-blocked}"
}

signal_other_authors() {
  if [[ -n "$PR" ]]; then
    local author
    author=$(pull '.user.login // empty')
    [[ -n "$author" && -n "$COMMITS" ]] || { answer ""; return; }
    answer "$(jq -r --arg a "$author" --argjson total "$(pull .commits)" "$NORM"'
      if length != $total then "unknown"
      elif any(.[]; (.parents | length) < 2 and ((.author.login // "") | norm) != ($a | norm))
      then "yes" else "no" end' <<<"$COMMITS" 2>/dev/null)"
    return
  fi
  history_ready || { answer ""; return; }
  local me email emails
  me=$(git config user.email 2>/dev/null)
  [[ -n "$me" ]] || { answer ""; return; }
  emails=$(git log --no-merges --format=%ae "$BASE_TIP..$HEAD_SHA" 2>/dev/null) || { answer ""; return; }
  while IFS= read -r email; do
    if [[ -n "$email" && "${email,,}" != "${me,,}" ]]; then
      answer yes
      return
    fi
  done <<<"$emails"
  answer no
}

signal_dependents() {
  [[ -n "$HEAD_REF" ]] || { answer ""; return; }
  count_answer "$(gh pr list -R "$REPO" --base="$HEAD_REF" --state open --limit 1 --json number --jq length 2>/dev/null | tr -d '\r')"
}

signal_base_merged() {
  history_ready || { answer ""; return; }
  local merges m
  merges=$(git rev-list --merges "$BASE_TIP..$HEAD_SHA" 2>/dev/null) || { answer ""; return; }
  for m in $merges; do
    if git merge-base --is-ancestor "$m^2" "$BASE_TIP" 2>/dev/null; then
      answer yes
      return
    fi
  done
  answer no
}

signal_human_review() {
  [[ -n "$PR" ]] || { answer no; return; }
  local reviews
  reviews=$(paged "repos/$REPO/pulls/$PR/reviews")
  [[ -n "$reviews" && -n "$COMMITS" ]] || { answer ""; return; }
  answer "$(jq -nr --argjson commits "$COMMITS" --argjson reviews "$reviews" '
    ($commits | map(.sha)) as $head
    | if any($reviews[];
        .user.type != "Bot" and ((.user.login // "") | endswith("[bot]") | not)
        and (.state | IN("APPROVED", "CHANGES_REQUESTED", "COMMENTED"))
        and (.commit_id as $id | $head | index($id)))
      then "yes" else "no" end' 2>/dev/null)"
}

signal_landing() {
  [[ -n "$RULES" && -n "$META" ]] || { answer ""; return; }
  case "$(jq -r 'map(select(.type == "merge_queue").parameters.merge_method) | .[0] // ""' <<<"$RULES")" in
    SQUASH) answer squash ;;
    ?*) answer keeps-commits ;;
    *)
      answer "$(jq -r 'if .squashMergeAllowed then "squash"
        elif .mergeCommitAllowed or .rebaseMergeAllowed then "keeps-commits"
        else empty end' <<<"$META" 2>/dev/null)"
      ;;
  esac
}

signal_overlap() {
  history_ready && [[ "$CHECKOUT_HEAD" == "$HEAD_SHA" ]] || { answer ""; return; }
  # Only a base shown to be the default branch may run its own overlap rule.
  local out flags=(--paths-only)
  [[ -z "$DEFAULT_BRANCH" || "$BASE" != "$DEFAULT_BRANCH" ]] || flags=()
  out=$(bash "$OVERLAP" ${flags[@]+"${flags[@]}"} "$PWD" "$BASE_TIP" 2>/dev/null)
  answer "${out%% *}"
}

# signal_base_change_needed <conflict> <native_stack> <behind> <overlap>
signal_base_change_needed() {
  if [[ "$BASE_FIXED" == 1 || "$1" == yes || "$4" == yes ]]; then
    answer yes
  elif [[ "$4" == no && ! ("$2" == yes && "$3" != no) ]]; then
    answer no
  else
    answer ""
  fi
}

# Sets SETTING and SETTING_LEVEL. The base branch is read, never the head, and
# only a default-branch base counts: any other is a branch the author may have
# pushed unreviewed.
read_setting() {
  SETTING=auto SETTING_LEVEL=default
  if [[ -z "$BASE" || -z "$DEFAULT_BRANCH" ]]; then
    notice "the base branch or the default branch could not be read; pr_update_method is unread"
    return
  fi
  if [[ "$BASE" != "$DEFAULT_BRANCH" ]]; then
    notice "base $BASE is not the default branch $DEFAULT_BRANCH; pr_update_method is unread"
    return
  fi
  base_file_read_key --http-response pr_update_method < <(gh api -i -X GET "repos/$REPO/contents/$CONVENTION_KEY_YAML_REL" -f ref="$BASE" -H "Accept: application/vnd.github.raw" 2>/dev/null)
  if [[ "$BASE_FILE_STATE" == failed ]]; then
    notice "$BASE_FILE_REASON; pr_update_method is unread"
    return
  fi
  ((BASE_FILE_HAS)) || return
  case "$BASE_FILE_VALUE" in
    auto | merge | rebase) SETTING="$BASE_FILE_VALUE" SETTING_LEVEL=repository ;;
    *) notice "pr_update_method '$BASE_FILE_VALUE' at $BASE is not auto, merge or rebase; using auto" ;;
  esac
}

PULL="" COMMITS="" RULES="" META="" HEAD_SHA="" HEAD_REF="" BASE_TIP="" CHECKOUT_HEAD="" DEFAULT_BRANCH=""
load
read_setting
behind=$(signal_behind)
conflict=$(signal_conflict)
native_stack=$(signal_native_stack)
overlap=$(signal_overlap)

jq -cn \
  --arg head_sha "${HEAD_SHA:-unknown}" \
  --arg setting "$SETTING" \
  --arg setting_level "$SETTING_LEVEL" \
  --arg behind "$behind" \
  --arg conflict "$conflict" \
  --arg up_to_date_required "$(signal_up_to_date_required)" \
  --arg base_change_needed "$(signal_base_change_needed "$conflict" "$native_stack" "$behind" "$overlap")" \
  --arg native_stack "$native_stack" \
  --arg managed_head "$(signal_managed_head)" \
  --arg rewrite "$(signal_rewrite)" \
  --arg other_authors "$(signal_other_authors)" \
  --arg dependents "$(signal_dependents)" \
  --arg base_merged "$(signal_base_merged)" \
  --arg human_review "$(signal_human_review)" \
  --arg landing "$(signal_landing)" \
  '$ARGS.named'
