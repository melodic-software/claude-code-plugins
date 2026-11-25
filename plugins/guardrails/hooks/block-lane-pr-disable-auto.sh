#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_LANE_PR_DISABLE_AUTO_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-lane-pr-disable-auto PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::buffer_stdin_to INPUT || exit 0

LPD_LC="${INPUT,,}"
LPD_BARE="${LPD_LC//[\"\'\\]/}"
[[ "$LPD_BARE" == *disable-auto* || "$LPD_BARE" == *disablepullrequestautomerge* ]] || exit 0

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || exit 0
((HOOK_JQ_FIELDS_NUL)) && exit 0
LPD_COMMAND="${HOOK_JQ_FIELDS[0]}"
LPD_TOOL="${HOOK_JQ_FIELDS[1]:-Bash}"
LPD_CWD="${HOOK_JQ_FIELDS[2]}"
[[ "$LPD_TOOL" == Bash && -n "$LPD_COMMAND" ]] || exit 0
((${#LPD_COMMAND} > 16384)) && exit 0

LANE_APP="${CLAUDE_PLUGIN_OPTION_BLOCK_LANE_PR_DISABLE_AUTO_APP:-}"
LANE_APP="${LANE_APP,,}"
LANE_APP="${LANE_APP#app/}"
LANE_APP="${LANE_APP%\[bot\]}"
[[ -n "$LANE_APP" ]] && LANE_APP="${LANE_APP}[bot]"

LPD_TARGETS=()
LPD_UNRESOLVED=""
LPD_CD=0
LPD_FOUND=0

# lpd::literal <word>: true when the word holds no `$` or backtick.
# shellcheck disable=SC2329  # reached from the parse callback
lpd::literal() { [[ "$1" != *'$'* && "$1" != *'`'* ]]; }

# lpd::cli [-R <repo> from before `merge`] <args after `merge`>
# shellcheck disable=SC2329  # reached from the parse callback
lpd::cli() {
  local a sel="" repo="" disable=0 flags=1
  while (($#)); do
    a="$1"
    shift
    if ((flags)); then
      case "$a" in
      --) flags=0 && continue ;;
      --disable-auto) disable=1 && continue ;;
      --disable-auto=*)
        [[ "${a#*=}" == false || "${a#*=}" == 0 ]] || disable=1
        continue
        ;;
      -R | --repo) repo="${1-}" && shift && continue ;;
      --repo=*) repo="${a#--repo=}" && continue ;;
      -R?*) repo="${a#-R}" && continue ;;
      -A | --author-email | -b | --body | -F | --body-file | --match-head-commit | -t | --subject)
        shift
        continue
        ;;
      -*) continue ;;
      *) ;;
      esac
    fi
    [[ -z "$sel" ]] && sel="$a"
  done
  ((disable)) || return 0
  LPD_FOUND=1
  if ! lpd::literal "$sel" || ! lpd::literal "$repo"; then
    LPD_UNRESOLVED="the pull request or repository is not literal"
  elif [[ -z "$sel" ]]; then
    LPD_UNRESOLVED="it names no pull request number or URL"
  else
    LPD_TARGETS+=("cli ${sel#\#} ${repo:--}")
  fi
}

# lpd::graphql_args <args after `gh api`>
# shellcheck disable=SC2329  # reached from the parse callback
lpd::graphql_args() {
  local a hit=0 ids=" " id
  for a in "$@"; do
    [[ "${a,,}" == *disablepullrequestautomerge* ]] && hit=1
  done
  ((hit)) || return 0
  LPD_FOUND=1
  for a in "$@"; do
    if [[ "$a" == query=* ]]; then
      # shellcheck disable=SC2016  # literal shell syntax, matched as text
      [[ "$a" != *'$('* && "$a" != *'${'* && "$a" != *'`'* ]]
    else
      lpd::literal "$a"
    fi || {
      LPD_UNRESOLVED="an argument is not literal"
      return 0
    }
    while [[ "$a" =~ (PR_[A-Za-z0-9_-]+) ]]; do
      id="${BASH_REMATCH[1]}"
      [[ "$ids" == *" $id "* ]] || ids+="$id "
      a="${a#*"$id"}"
    done
  done
  read -r id a <<<"$ids"
  if [[ -z "$id" || -n "$a" ]]; then
    LPD_UNRESOLVED="the mutation does not name exactly one literal PR_ node id"
  else
    LPD_TARGETS+=("node $id")
  fi
}

# hook::bash_parse_segments callback: one segment's argv words.
# shellcheck disable=SC2329  # invoked through hook::bash_parse_segments
lpd::segment() {
  while (($#)); do
    case "$1" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until | command | time | exec | nohup | -p | --) shift ;;
    *)
      [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || break
      shift
      ;;
    esac
  done
  (($#)) || return 0
  local cmd="${1##*/}" pre_repo=""
  cmd="${cmd,,}"
  cmd="${cmd%.exe}"
  shift
  case "$cmd" in
  cd | pushd | popd)
    LPD_CD=1
    return 0
    ;;
  gh) ;;
  *) return 0 ;;
  esac
  if [[ "${1-}" == api ]]; then
    shift
    local -a all=("$@")
    local endpoint=""
    while (($#)); do
      case "$1" in
      -X | --method | -f | --raw-field | -F | --field | -H | --header | --input | -q | --jq | -t | --template | --hostname | --cache | -p | --preview)
        shift
        (($#)) && shift
        ;;
      -*) shift ;;
      *)
        endpoint="$1"
        break
        ;;
      esac
    done
    [[ "$endpoint" == graphql || "$endpoint" == /graphql ]] && lpd::graphql_args ${all[@]+"${all[@]}"}
    return 0
  fi
  [[ "${1-}" == pr ]] || return 0
  shift
  while (($#)); do
    case "$1" in
    -R | --repo)
      pre_repo="${2-}"
      shift
      (($#)) && shift
      ;;
    --repo=*) pre_repo="${1#--repo=}" && shift ;;
    -R?*) pre_repo="${1#-R}" && shift ;;
    *) break ;;
    esac
  done
  if ! lpd::literal "${1-}"; then
    local w
    for w in "$@"; do [[ "$w" == --disable-auto ]] && LPD_FOUND=1 && LPD_UNRESOLVED="the gh pr subcommand $1 is not literal"; done
    return 0
  fi
  [[ "${1-}" == merge ]] || return 0
  shift
  lpd::cli ${pre_repo:+-R "$pre_repo"} "$@"
  return 0
}

hook::bash_parse_segments "$LPD_COMMAND" lpd::segment

LPD_CMD_BARE="${LPD_COMMAND,,}"
LPD_CMD_BARE="${LPD_CMD_BARE//[\"\'\\]/}"
LPD_BT=0
LPD_SHAPE_RE='pr.*merge.*disable-auto|disablepullrequestautomerge'
[[ "$LPD_COMMAND" == *'`'* ]] &&
  { ((LPD_FOUND)) || [[ "$LPD_CMD_BARE" =~ $LPD_SHAPE_RE ]]; } && LPD_BT=1
((LPD_FOUND || LPD_BT)) || exit 0

lpd::block() {
  printf '%s\n' "$@" 'Only the user can turn this guard off (block_lane_pr_disable_auto_enabled).' >&2
  exit 2
}

# shellcheck disable=SC2016  # $(...) is literal text in the message
LPD_LITERAL_FIX='Fix: write the target literally, gh pr merge <number> -R owner/repo --disable-auto, with no shell variable, $(...) or backticks. To hold a lanes App pull request, add the do-not-merge label instead.'
((LPD_BT)) &&
  lpd::block "BLOCKED: guardrails could not tell which pull request this auto-merge disable targets (the command holds a backtick)." "$LPD_LITERAL_FIX"
[[ -z "$LPD_UNRESOLVED" ]] ||
  lpd::block "BLOCKED: guardrails could not tell which pull request this auto-merge disable targets ($LPD_UNRESOLVED)." "$LPD_LITERAL_FIX"

if ! command -v gh >/dev/null 2>&1; then
  hook::notice_once guardrails-lane-pr-disable-auto-gh "$INPUT" &&
    hook::emit_skip_notice PreToolUse "guardrails block-lane-pr-disable-auto: gh is not on PATH, so the author of the pull request this auto-merge disable targets was not checked. To hold a lanes App pull request, add the do-not-merge label instead. This notice does not repeat this session."
  exit 0
fi

LPD_OUT=""
LPD_ERR=""
lpd::gh() {
  local errf rc=0
  local -a cap=()
  command -v timeout >/dev/null 2>&1 && cap=(timeout 15)
  errf="$(mktemp 2>/dev/null)" || errf=/dev/null
  LPD_OUT=$(
    [[ -n "$LPD_CWD" ]] && cd "$LPD_CWD" 2>/dev/null
    export GH_PROMPT_DISABLED=1
    ${cap[@]+"${cap[@]}"} gh "$@" 2>"$errf"
  ) || rc=$?
  LPD_ERR=""
  if [[ "$errf" != /dev/null ]]; then
    IFS= read -r LPD_ERR <"$errf" || :
    rm -f "$errf"
  fi
  [[ -n "$LPD_ERR" ]] || LPD_ERR="gh exited $rc"
  LPD_ERR="${LPD_ERR:0:200}"
  return "$rc"
}

LPD_GHREPO=0
[[ "$LPD_CMD_BARE" == *gh_repo* || "$LPD_CMD_BARE" == *gh_host* ]] && LPD_GHREPO=1

lpd::check() {
  local kind sel repo what login kindof="" hold
  read -r kind sel repo <<<"$1"
  if [[ "$kind" == node ]]; then
    what="node $sel"
    # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
    lpd::gh api graphql -f query='query($id:ID!){node(id:$id){... on PullRequest{number repository{nameWithOwner} author{login __typename}}}}' \
      -f id="$sel" --jq '.data.node | "\(.repository.nameWithOwner)#\(.number) \(.author.login) \(.author.__typename)"' ||
      lpd::block "BLOCKED: guardrails could not read the author of pull request $what ($LPD_ERR), so it cannot tell whether the lanes App opened it." "$LPD_LITERAL_FIX"
    read -r what login kindof <<<"$LPD_OUT"
  else
    what="$sel"
    if [[ "$repo" == - ]]; then
      repo=""
      if [[ ! "$sel" =~ ^https?:// ]] && ((LPD_CD || LPD_GHREPO)); then
        lpd::block "BLOCKED: guardrails could not tell which repository this auto-merge disable runs in (the command changes directory or names GH_REPO or GH_HOST, and names no -R repository)." "$LPD_LITERAL_FIX"
      fi
    else
      what="$repo#$sel"
    fi
    lpd::gh pr view "$sel" ${repo:+-R "$repo"} --json author --jq '.author.login' ||
      lpd::block "BLOCKED: guardrails could not read the author of pull request $what ($LPD_ERR), so it cannot tell whether the lanes App opened it." "$LPD_LITERAL_FIX"
    login="$LPD_OUT"
  fi
  login="${login,,}"
  [[ "$kindof" == Bot || "$login" == app/* || "$login" == *"[bot]" ]] && kindof=Bot
  login="${login#app/}"
  login="${login%\[bot\]}[bot]"
  if [[ "$login" == "$LANE_APP" ]]; then
    hold="gh pr edit <number> -R owner/repo --add-label do-not-merge"
    [[ "$kind" == cli && -n "$repo" && "$sel" =~ ^[0-9]+$ ]] && hold="gh pr edit $sel -R $repo --add-label do-not-merge"
    lpd::block "BLOCKED: pull request $what was opened by the lanes App ($LANE_APP). Turning off its auto-merge from this session reads as the owner's veto, and the pr-merge lane then never arms it again." \
      "Fix: hold it with the do-not-merge label instead ($hold). The lane disarms auto-merge while the label is on, and re-arms the pull request by itself when the label comes off."
  fi
  if [[ -z "$LANE_APP" && "$kindof" == Bot ]]; then
    lpd::block "BLOCKED: pull request $what was opened by a GitHub App, and block_lane_pr_disable_auto_app is unset, so guardrails cannot tell whether it is the lanes App." \
      "Fix: set block_lane_pr_disable_auto_app to the lanes App login. To hold a lanes App pull request, add the do-not-merge label instead."
  fi
  return 0
}

for LPD_T in ${LPD_TARGETS[@]+"${LPD_TARGETS[@]}"}; do
  lpd::check "$LPD_T"
done
exit 0
