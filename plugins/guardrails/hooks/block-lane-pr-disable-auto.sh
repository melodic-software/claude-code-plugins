#!/usr/bin/env bash
# PreToolUse hook: block turning off auto-merge on a pull request the lanes App
# opened, and point to the do-not-merge label instead.
#
# WHY. The pr-merge lane leaves an unarmed lanes App PR alone when the newest
# of its auto-merge events is a disable by a User
# (.github/scripts/pr-merge/enable-auto-merge.mjs, the AutoMergeDisabledEvent
# check). An agent session runs under the owner's login, so its
# `gh pr merge <n> --disable-auto` reads as the owner's veto, and the lane never
# arms that PR again until a person enables auto-merge or queues it. The
# do-not-merge label is the hold to use: the lane disarms the PR while the
# label is on and re-arms it by itself when the label comes off.
#
# MATCHED, on the Bash tool, at a command position (leading NAME=value words
# and the `command`, `time`, `exec` and `nohup` prefixes are stepped over):
#   gh CLI   `gh pr merge` with `--disable-auto` (or `--disable-auto=<v>`, `v`
#            not false or 0), `-R` before or after `merge`.
#   GraphQL  `gh api ... graphql` whose arguments name the
#            `disablePullRequestAutoMerge` mutation. The PR is the one
#            `PR_...` node id in the arguments.
# Each target's author is read with one call: `gh pr view <n> -R <repo> --json
# author` for the CLI form, a GraphQL `node` query for the mutation. The
# command is blocked when the author is the lanes App (LANE_APP below); gh
# reports an App author as `app/<slug>` and GraphQL as `<slug>`, and both are
# read as `<slug>[bot]`.
#
# FAILS CLOSED on a target it cannot read: a PR number, repo or node id that
# comes from a shell variable, `$(...)` or backticks; a backtick anywhere in a
# command that names the disable; a `gh pr merge --disable-auto` with no PR
# number or URL; one with no -R in a command that changes directory or names
# GH_REPO or GH_HOST; a mutation with no literal `PR_...` id or more than one;
# and an author read that fails. Each block names the literal form to use.
#
# NOT MATCHED: `gh pr merge` without `--disable-auto`; a PR by any other
# author; the PowerShell tool; a mutation read from a file (`-F query=@file`,
# `--input`); a command word from an expansion (`$GH pr merge`); a disable from
# a script, a child shell (`bash -c`), `eval`, a wrapper such as `sudo` or
# `env`, or the web UI. With gh not on the hook's PATH, a target the guard
# can read passes unchecked; an unreadable one is still blocked.
#
# Kill switch: block_lane_pr_disable_auto_enabled userConfig option.
#
# BLOCKING: exits 2 with the hold-label fix.

set -uo pipefail

# Kill switch FIRST, above every source. scripts/check-killswitch-hoist.sh
# pins this line.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_LANE_PR_DISABLE_AUTO_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-lane-pr-disable-auto PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::buffer_stdin_to INPUT || exit 0

# jq-free pre-filter, on a copy with quotes and backslashes dropped so
# `--disable-au"to"` still matches.
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

LPD_TARGETS=()     # one per disable: "cli <selector> <repo>" or "node <id>"
LPD_UNRESOLVED=""  # set: why a target cannot be read, and the command is refused
LPD_CD=0           # 1: a segment changes directory
LPD_FOUND=0        # 1: the command holds a disable

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
      # gh takes a boolean flag's value after `=`.
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
    # A value from a shell expansion may be the node id. The query may hold
    # GraphQL `$name` variables, so there only `$(`, `${` and a backtick count.
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
    # The endpoint is the first word that is not a flag or a flag's value.
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
    # `gh pr $VERB 5 --disable-auto`: the subcommand may be merge.
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
# A backtick substitution can change or hide the target the parse reads, so
# disable-shaped text with a backtick anywhere in the command is refused.
LPD_BT=0
LPD_SHAPE_RE='pr.*merge.*disable-auto|disablepullrequestautomerge'
[[ "$LPD_COMMAND" == *'`'* ]] &&
  { ((LPD_FOUND)) || [[ "$LPD_CMD_BARE" =~ $LPD_SHAPE_RE ]]; } && LPD_BT=1
((LPD_FOUND || LPD_BT)) || exit 0

# lpd::block <line>...: print the lines and the turn-off note, and exit 2.
lpd::block() {
  printf '%s\n' "$@" 'Only the user can turn this guard off (block_lane_pr_disable_auto_enabled).' >&2
  exit 2
}

[[ -n "$LANE_APP" ]] ||
  lpd::block "BLOCKED: guardrails cannot tell which App is the lanes App: block_lane_pr_disable_auto_app is unset." \
    "Fix: set block_lane_pr_disable_auto_app to the lanes App login. To hold a lanes App pull request, add the do-not-merge label instead."

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
# lpd::gh <arg>...: one gh call from the payload's cwd, capped at 15 s where
# `timeout` exists. Sets LPD_OUT and LPD_ERR (the first line of stderr).
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

# lpd::check <target>: read one target's author and block when it is the
# lanes App.
lpd::check() {
  local kind sel repo what login hold
  read -r kind sel repo <<<"$1"
  if [[ "$kind" == node ]]; then
    what="node $sel"
    # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
    lpd::gh api graphql -f query='query($id:ID!){node(id:$id){... on PullRequest{number repository{nameWithOwner} author{login}}}}' \
      -f id="$sel" --jq '.data.node | "\(.repository.nameWithOwner)#\(.number) \(.author.login)"' ||
      lpd::block "BLOCKED: guardrails could not read the author of pull request $what ($LPD_ERR), so it cannot tell whether the lanes App opened it." "$LPD_LITERAL_FIX"
    read -r what login <<<"$LPD_OUT"
  else
    what="$sel"
    if [[ "$repo" == - ]]; then
      repo=""
      # Without -R or a URL gh reads the repository from the working directory
      # and the environment, which a cd or GH_REPO in the command changes.
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
  login="${login#app/}"
  login="${login%\[bot\]}[bot]"
  if [[ "$login" == "$LANE_APP" ]]; then
    hold="gh pr edit <number> -R owner/repo --add-label do-not-merge"
    [[ "$kind" == cli && -n "$repo" && "$sel" =~ ^[0-9]+$ ]] && hold="gh pr edit $sel -R $repo --add-label do-not-merge"
    lpd::block "BLOCKED: pull request $what was opened by the lanes App ($LANE_APP). Turning off its auto-merge from this session reads as the owner's veto, and the pr-merge lane then never arms it again." \
      "Fix: hold it with the do-not-merge label instead ($hold). The lane disarms auto-merge while the label is on, and re-arms the pull request by itself when the label comes off."
  fi
  return 0
}

for LPD_T in ${LPD_TARGETS[@]+"${LPD_TARGETS[@]}"}; do
  lpd::check "$LPD_T"
done
exit 0
