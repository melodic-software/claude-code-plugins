#!/usr/bin/env bash
# PreToolUse hook, the merge guard: refuse a pull-request merge the PR's own
# state does not allow (#6463, https://github.com/melodic-software/claude-code-plugins/issues/18822).

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_MERGE_GUARD_ENABLED:-true}" == "false" ]] && exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary merge-guard PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

_bupm_enabled="${CLAUDE_PLUGIN_OPTION_MERGE_GUARD_ENABLED:-true}"
start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0
[[ "$_bupm_enabled" == true ]] ||
  guard::bad_switch_notice merge_guard_enabled "$_bupm_enabled" "$INPUT"

hook::require jq PreToolUse guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || exit 0
COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
BUPM_CWD="${HOOK_JQ_FIELDS[2]}"

BUPM_FORM=""  # gh-pr-merge | rest-merge | ccr-auto-merge | graphql | mcp | backtick
BUPM_AUTO=0   # 1: the request waits for checks (auto-merge or merge queue)
BUPM_REPO=""  # owner/repo, may hold gh's {owner}/{repo} placeholders
BUPM_NUM=""
BUPM_SEL=""   # gh pr merge selector: number, URL or branch; empty = current branch
BUPM_NODE=""  # GraphQL PullRequest node id
BUPM_UNRESOLVED=""
BUPM_MERGES=0
BUPM_BT=0
BUPM_CONT=0
BUPM_CD=0     # 1: a segment changes directory (cd, pushd, popd, Set-Location)
BUPM_GHREPO=0 # 1: the command text names GH_REPO or GH_HOST
BUPM_HOST=""  # a host other than github.com that qualified the repo
BUPM_SHELL=0
BUPM_UNLABEL=0
BUPM_UNLABEL_VAR=0
BUPM_UNLABEL_IDS=""
BUPM_UNLABEL_GQL=0

# shellcheck disable=SC2329  # reached from the recorders below
_bupm_literal() { [[ "$1" != *'$'* && "$1" != *'`'* ]]; }

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$2"
  hook::emit_telemetry "merge-guard" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

_bupm_mutation_re='(mergePullRequest|enablePullRequestAutoMerge|enqueuePullRequest)'

# shellcheck disable=SC2329  # reached from the recorders below
_bupm_unlabel_value() {
  if ! _bupm_literal "$1"; then
    BUPM_UNLABEL_VAR=1
  elif [[ ",${1,,}," =~ ,[[:space:]]*pr-verify-failed[[:space:]]*, ]]; then
    BUPM_UNLABEL=1
  fi
}

# shellcheck disable=SC2329
_bupm_label_edit() {
  local a
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    --remove-label)
      _bupm_unlabel_value "${1-}"
      (($#)) && shift
      ;;
    --remove-label=*) _bupm_unlabel_value "${a#*=}" ;;
    *) ;;
    esac
  done
  return 1
}

# _bupm_rest_path <path> <method>: record a REST merge or cloud auto-merge PUT.
# shellcheck disable=SC2329
_bupm_rest_path() {
  local p="$1" m="${2^^}" route_re='^repos/.+/pulls/[^/]+/(merge|ccr/auto_merge)$'
  p="${p#https://api.github.com}"
  p="${p#http://api.github.com}"
  p="${p#/}"
  p="${p%%\?*}"
  p="${p%/}"
  if [[ "$p" =~ ^repos/[^/]+/[^/]+/issues/[^/]+/labels/(.+)$ ]] && { [[ "$m" == DELETE ]] || ! _bupm_literal "$m"; }; then
    local label="${BASH_REMATCH[1]}"
    _bupm_literal "$label" && printf -v label '%b' "${label//%/\\x}"
    _bupm_unlabel_value "$label"
    return 1
  fi
  if [[ "$m" != PUT ]]; then
    _bupm_literal "$m" && return 1
    [[ "$p" =~ $route_re ]] || return 1
    BUPM_FORM="rest-merge"
    BUPM_UNRESOLVED="the method $2 is not literal"
    return 0
  fi
  if [[ "$p" =~ $route_re ]] && ! _bupm_literal "$p"; then
    BUPM_FORM="rest-merge"
    BUPM_UNRESOLVED="the route $p is not literal"
    return 0
  fi
  [[ "$p" =~ ^repos/([^/]+/[^/]+)/pulls/([0-9]+)/(merge|ccr/auto_merge)$ ]] || return 1
  BUPM_REPO="${BASH_REMATCH[1]}"
  BUPM_NUM="${BASH_REMATCH[2]}"
  if [[ "${BASH_REMATCH[3]}" == merge ]]; then
    BUPM_FORM="rest-merge"
  else
    BUPM_FORM="ccr-auto-merge"
    BUPM_AUTO=1
  fi
}

# _bupm_graphql <arg>...: record a merge mutation named anywhere in the args.
# shellcheck disable=SC2329
_bupm_graphql() {
  local a hit="" unlabel=0 ids=" " lid
  for a in "$@"; do
    [[ "$a" =~ $_bupm_mutation_re ]] && hit="${BASH_REMATCH[1]}"
    [[ "$a" == *removeLabelsFromLabelable* ]] && unlabel=1
  done
  if ((unlabel)); then
    for a in "$@"; do
      while [[ "$a" =~ (LA_[A-Za-z0-9_-]+) ]]; do
        lid="${BASH_REMATCH[1]}"
        [[ "$ids" == *" $lid "* ]] || ids+="$lid "
        a="${a#*"$lid"}"
      done
    done
    read -r BUPM_UNLABEL_IDS <<<"$ids"
    [[ -n "$BUPM_UNLABEL_IDS" ]] || BUPM_UNLABEL_GQL=1
  fi
  [[ -n "$hit" ]] || return 1
  BUPM_FORM=graphql
  [[ "$hit" == mergePullRequest ]] || BUPM_AUTO=1
  # shellcheck disable=SC2016  # regexes, `$` is a literal character
  local bind_re='pullRequestId[[:space:]]*:[[:space:]]*(\\?"(PR_[A-Za-z0-9_-]+)|\$([A-Za-z_][A-Za-z0-9_]*))'
  local text rest id var val node="" vals
  printf -v text '%s\n' "$@"
  rest="$text"
  while [[ "$rest" =~ $bind_re ]]; do
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    id="${BASH_REMATCH[2]}"
    var="${BASH_REMATCH[3]}"
    if [[ -n "$var" ]]; then
      vals=""
      for a in "$@"; do
        [[ "$a" =~ ^${var}=(PR_[A-Za-z0-9_-]+)$ ]] && vals+="${BASH_REMATCH[1]} "
      done
      val="$text"
      while [[ "$val" =~ \\?\"${var}\\?\"[[:space:]]*:[[:space:]]*\\?\"(PR_[A-Za-z0-9_-]+) ]]; do
        vals+="${BASH_REMATCH[1]} "
        val="${val#*"${BASH_REMATCH[0]}"}"
      done
      read -r id _ <<<"$vals"
      [[ -n "$id" ]] || return 0
      for val in $vals; do [[ "$val" == "$id" ]] || return 0; done
    fi
    [[ -z "$node" || "$node" == "$id" ]] || return 0
    node="$id"
  done
  BUPM_NODE="$node"
}

# gh pr merge <args>
# shellcheck disable=SC2329
_bupm_gh_pr_merge() {
  local a sel="" repo="" auto=0 flags=1 why=""
  while (($#)); do
    a="$1"
    shift
    if ((flags)); then
      case "$a" in
      --) flags=0 && continue ;;
      --disable-auto | --help | -h) return 1 ;;
      --auto) auto=1 && continue ;;
      -R | --repo)
        (($#)) || why="the -R value is missing"
        repo="${1-}" && shift && continue
        ;;
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
  BUPM_FORM=gh-pr-merge
  BUPM_AUTO=$auto
  BUPM_REPO="$repo"
  BUPM_SEL="$sel"
  _bupm_literal "$repo" || why="the repository $repo is not literal"
  _bupm_literal "$sel" || why="the pull request $sel is not literal"
  BUPM_UNRESOLVED="$why"
}

# gh api <args>
# shellcheck disable=SC2329
_bupm_gh_api() {
  local -a all=("$@")
  local a method="" endpoint=""
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    -X | --method) method="${1-}" && shift && continue ;;
    --method=*) method="${a#--method=}" && continue ;;
    -X?*) method="${a#-X}" && continue ;;
    -f | --raw-field | -F | --field | -H | --header | --input | -q | --jq | -t | --template | --hostname | --cache | -p | --preview)
      shift
      continue
      ;;
    -*) continue ;;
    *) ;;
    esac
    [[ -z "$endpoint" ]] && endpoint="$a"
  done
  if [[ "$endpoint" == graphql || "$endpoint" == /graphql ]]; then
    _bupm_graphql "${all[@]}"
    return
  fi
  _bupm_rest_path "$endpoint" "$method"
}

# curl <args>
# shellcheck disable=SC2329
_bupm_curl() {
  local -a all=("$@")
  local a method="" url="" upload=0
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    -X | --request) method="${1-}" && shift && continue ;;
    --request=*) method="${a#--request=}" && continue ;;
    -X?*) method="${a#-X}" && continue ;;
    -T | --upload-file) upload=1 && shift && continue ;;
    --upload-file=* | -T?*) upload=1 && continue ;;
    *) ;;
    esac
    [[ "$a" == *api.github.com/* && -z "$url" ]] && url="$a"
  done
  [[ -z "$method" ]] && ((upload)) && method=PUT
  [[ -n "$url" ]] || return 1
  if [[ "${url%%\?*}" =~ api\.github\.com/graphql/?$ ]]; then
    _bupm_graphql "${all[@]}"
    return
  fi
  _bupm_rest_path "${url#*api.github.com}" "$method"
}

# shellcheck disable=SC2329  # reached from _bupm_segment
_bupm_is_cd() {
  while (($#)); do
    case "$1" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until | command | builtin | time | exec | nohup | -p | --) shift ;;
    *) break ;;
    esac
  done
  local w="${1-}"
  case "${w,,}" in cd | pushd | popd | chdir | set-location | push-location | pop-location | sl) return 0 ;; *) return 1 ;; esac
}

# shellcheck disable=SC2329  # invoked through hook::bash_parse_segments
_bupm_segment() {
  ((BUPM_MERGES == 0)) && _bupm_is_cd "$@" && BUPM_CD=1
  _bupm_runs_shell "$@" && BUPM_SHELL=1
  _bupm_command "$@" && ((++BUPM_MERGES))
  return 0
}

# shellcheck disable=SC2329  # reached from _bupm_segment
_bupm_runs_shell() {
  local w lead=1
  for w in "$@"; do
    if ((lead)); then
      case "$w" in
      '{' | '}' | '!' | then | do | else | elif | if | while | until | command | builtin | time | exec | nohup | -p | --) continue ;;
      *) ;;
      esac
      [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue
      lead=0
      _bupm_literal "$w" || return 0
      [[ "$w" != '[' && "$w" != '[[' && "$w" == *[\*\?\[]* ]] && return 0
      case "${w,,}" in eval | source | . | *.sh) return 0 ;; *) ;; esac
    fi
    w="${w##*/}"
    w="${w##*\\}"
    w="${w,,}"
    case "${w%.exe}" in
    bash | sh | zsh | dash | ksh | mksh | ash | yash | csh | tcsh | fish | busybox | pwsh | powershell | sudo | doas | su | ssh | at | batch) return 0 ;;
    *) ;;
    esac
  done
  return 1
}

# shellcheck disable=SC2329  # reached from _bupm_segment
_bupm_command() {
  while (($#)); do
    case "$1" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until | command | time | exec | nohup | -p | --) shift ;;
    *)
      [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || break
      shift
      ;;
    esac
  done
  (($#)) || return 1
  local cmd="${1##*/}"
  cmd="${cmd##*\\}"
  cmd="${cmd,,}"
  cmd="${cmd%.exe}"
  shift
  case "$cmd" in
  gh)
    if [[ "${1-}" == pr ]]; then
      local pre_repo=""
      shift
      while (($#)); do
        case "$1" in
        -R | --repo) pre_repo="${2-}" && shift 2 ;;
        --repo=*) pre_repo="${1#--repo=}" && shift ;;
        -R?*) pre_repo="${1#-R}" && shift ;;
        *) break ;;
        esac
      done
      if [[ "${1-}" == *[\$\`]* ]]; then
        BUPM_FORM=gh-pr-merge
        BUPM_UNRESOLVED="the gh pr subcommand $1 is not literal"
        return 0
      fi
      [[ "${1-}" == edit ]] && _bupm_label_edit "${@:2}"
      [[ "${1-}" == merge ]] || return 1
      shift
      _bupm_gh_pr_merge ${pre_repo:+-R "$pre_repo"} "$@"
    elif [[ "${1-}" == label && ("${2-}" == delete || "${2-}" == edit) ]]; then
      local w
      set -- "${@:3}"
      while (($#)); do
        w="$1"
        shift
        case "$w" in
        -R | --repo | -n | --name | -d | --description | -c | --color) (($#)) && shift ;;
        -*) ;;
        *)
          _bupm_unlabel_value "$w"
          break
          ;;
        esac
      done
      return 1
    elif [[ "${1-}" == issue ]]; then
      _bupm_label_edit "${@:2}"
    elif [[ "${1-}" == api ]]; then
      _bupm_gh_api "${@:2}"
    else
      return 1
    fi
    ;;
  curl) _bupm_curl "$@" ;;
  *) return 1 ;;
  esac
}

if [[ "$TOOL_NAME" =~ ^mcp__.+__(merge_pull_request|enable_pr_auto_merge)$ ]]; then
  BUPM_FORM=mcp
  [[ "${BASH_REMATCH[1]}" == enable_pr_auto_merge ]] && BUPM_AUTO=1
  hook::jq_fields "$INPUT" '.tool_input.owner' '.tool_input.repo' '.tool_input.pullNumber' || exit 0
  BUPM_REPO="${HOOK_JQ_FIELDS[0]}/${HOOK_JQ_FIELDS[1]}"
  BUPM_NUM="${HOOK_JQ_FIELDS[2]%.0}"
else
  [[ -n "$COMMAND" ]] || exit 0
  ((${#COMMAND} > 16384)) && exit 0
  _bupm_lc="${COMMAND,,}"
  _bupm_joined="${_bupm_lc//$'\\\n'/}"
  _bupm_bare="${_bupm_joined//[\"\'\\]/}"
  _bupm_pre_re='merge|enqueue|pr-verify-failed|removelabelsfromlabelable|labels/[^[:space:]]*%'
  [[ "$_bupm_joined" =~ $_bupm_pre_re || "$_bupm_bare" =~ $_bupm_pre_re ]] || exit 0
  [[ "$_bupm_lc" == *gh_repo* || "$_bupm_bare" == *gh_repo* ||
    "$_bupm_lc" == *gh_host* || "$_bupm_bare" == *gh_host* ]] && BUPM_GHREPO=1
  # shellcheck disable=SC2016  # the backticks are literal regex text
  _bupm_rest_re='pulls/([^/[:space:]`]|`[^`]*`)+/(ccr/auto_)?merge'
  _bupm_pr_re='(^|[^a-z0-9_-])pr[[:space:]]+((-r|--repo)[=[:space:]]*[^[:space:]]+[[:space:]]+)*merge'
  _bupm_cli_re="$_bupm_pr_re|$_bupm_rest_re"
  _bupm_gql_re='mergepullrequest|enqueuepullrequest|enablepullrequestautomerge'
  _bupm_gh_pr_shaped() {
    local text="$_bupm_joined" seen="" m lead before word w1 w2 w3 t i toks
    local redir_re='^[0-9]*&?[<>]+&?[^[:space:]]+$' redir_op_re='^[0-9]*&?[<>]+&?$'
    while [[ "$text" =~ $_bupm_pr_re ]]; do
      m="${BASH_REMATCH[0]}"
      lead="${BASH_REMATCH[1]}"
      before="${text%%"$m"*}"
      text="${text#*"$m"}"
      [[ -n "$lead" ]] || {
        seen+="$m"
        continue
      }
      word="$seen$before"
      seen+="$before$m"
      [[ "$lead" =~ [[:space:]] ]] || word+="$lead"
      toks=()
      read -rd '' -a toks <<<"$word"
      i=$((${#toks[@]} - 1))
      ((i >= 0)) && [[ "${toks[i]}" == *[\$\`]* ]] && return 0
      [[ "$lead" == [';|&(){}<>!'] ]] && continue
      ((i >= 0)) && [[ "${toks[i]}" == [\"\'] ]] && continue
      while ((i >= 0)); do
        t="${toks[i]}"
        [[ "$t" == *[\$\`]* ]] && return 0
        if [[ "$t" =~ ^[\"\'\\]+$ || "$t" =~ $redir_re ]]; then
          ((i -= 1))
        elif ((i > 0)) && [[ "${toks[i - 1]}" =~ $redir_op_re ]]; then
          ((i -= 2))
        else
          break
        fi
      done
      ((i >= 0)) || continue
      word="${toks[i]}"
      w1="${word//[\"\']/}"
      w1="${w1##*[/;|&()\{\}<>=!]}"
      w1="${w1##*\\}"
      w2="${word//[\"\'\\]/}"
      w2="${w2##*[/;|&()\{\}<>=!]}"
      w3="${word//[\"\'\\]/}"
      w3="${w3%%[<>]*}"
      w3="${w3##*[/;|&()\{\}=!]}"
      [[ "${w1%.exe}" == gh || "${w2%.exe}" == gh || "${w3%.exe}" == gh ]] && return 0
    done
    return 1
  }
  # shellcheck disable=SC2329  # invoked through hook::_c_locale
  _bupm_strip_bodies() {
    local e s t q c d pre body at=0 out=""
    _bupm_text="$COMMAND"
    ((BUPM_SHELL)) && return 0
    for e in ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}; do
      s="${e%% *}"
      e="${e#* }"
      t="${e%% *}"
      e="${e#* }"
      q="${e%% *}"
      e="${e#* }"
      c="${e%% *}"
      d="${e#* }"
      pre="${COMMAND:at:s-at}"
      # shellcheck disable=SC2016  # literal shell syntax
      [[ "$out$pre" == *'`'* || "$out$pre" == *'$('* || "$out$pre" == *'${'* ||
        "$out$pre" == *'$['* || "$out$pre" == *'(('* || "$out$pre" == *'[['* ]] && break
      body="${COMMAND:s:t-s}"
      out+="$pre"
      at=$t
      [[ "$q" == 1 && "$c" == 1 && "$d" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ &&
        "$body" != *$'\\\n'* && ! "${body,,}" =~ $_bupm_gql_re ]] && continue
      out+="$body"
    done
    _bupm_text="$out${COMMAND:at}"
  }
  if [[ "$TOOL_NAME" == PowerShell ]]; then
    declare -F guard::require_libs >/dev/null || source "$_HOOK_SELF/guard-requires.sh"
    guard::require_libs
    _bupm_ps=""
    ps::_bash_ready_to _bupm_ps "${COMMAND//\`/}"
    hook::bash_parse_segments "$_bupm_ps" _bupm_segment
  else
    hook::bash_parse_segments "$COMMAND" _bupm_segment
  fi
  _bupm_text="$COMMAND"
  hook::_c_locale _bupm_strip_bodies
  _bupm_joined="${_bupm_text,,}"
  _bupm_joined="${_bupm_joined//$'\\\n'/}"
  if [[ "$TOOL_NAME" != PowerShell && "$_bupm_text" == *'`'* ]] &&
    { [[ "$_bupm_joined" =~ $_bupm_rest_re|$_bupm_gql_re ]] || _bupm_gh_pr_shaped; }; then
    BUPM_BT=1
    BUPM_FORM=backtick
  elif [[ "$TOOL_NAME" != PowerShell && "$_bupm_text" == *$'\\\n'* && "$_bupm_joined" =~ $_bupm_cli_re ]]; then
    BUPM_CONT=1
    BUPM_FORM=continuation
  else
    [[ -n "$BUPM_FORM$BUPM_UNLABEL_IDS" ]] || ((BUPM_UNLABEL || BUPM_UNLABEL_VAR || BUPM_UNLABEL_GQL)) || exit 0
  fi
fi

# shellcheck source=merge-readiness.sh
source "$_HOOK_SELF/merge-readiness.sh" || exit 70

BUPM_OUT=""
BUPM_ERR=""
_bupm_api() {
  local rc=0
  MG_CWD="$BUPM_CWD" MG_HOST="$BUPM_HOST"
  _mg_api "$@" || rc=$?
  BUPM_OUT="$MG_OUT" BUPM_ERR="$MG_ERR"
  return "$rc"
}
_bupm_urlencode() { _mg_urlencode "$@"; }

_bupm_unchecked() {
  local what="this pull request"
  [[ -n "$BUPM_NUM" ]] && what="${BUPM_REPO}#${BUPM_NUM}"
  local subject="${2:-unresolved review threads, change requests or failing checks}" read="the PR's review threads and checks"
  [[ -n "${2-}" ]] && read="$2"
  local msg="guardrails merge-guard: could not check $what for $subject ($1), so this merge will run unchecked. Read $read yourself before relying on it."
  hook::emit_channels PreToolUse "$msg" "$msg"
  emit_tel "unchecked" "$BUPM_FORM"
  exit 0
}

_bupm_block() {
  local form="$1"
  shift
  printf '%s\n' "$@" 'Only the user can turn this guard off (merge_guard_enabled).' >&2
  emit_tel "blocked" "$form"
  exit 2
}

_bupm_refuse() {
  _bupm_block graphql-unresolvable \
    "BLOCKED: this GraphQL merge mutation could not be checked for unresolved review threads, change requests or failing checks ($1)." \
    'Fix: pass the pull request id as a literal (-f id=PR_...), or merge with gh pr merge <number>, so the PR can be checked.'
}

_bupm_refuse_target() {
  # shellcheck disable=SC2016  # $(...) is literal text in the message
  _bupm_block "$BUPM_FORM-unresolvable" \
    "BLOCKED: guardrails could not tell which pull request this merge targets ($1), so it could not check it for unresolved review threads, change requests or failing checks." \
    'Fix: write the repository and PR number literally: gh pr merge <number> -R owner/repo (or PUT repos/owner/repo/pulls/<number>/merge). A shell variable, $(...) or backticks hide the target; in a loop, write each merge as its own literal command.'
}
if [[ -n "$BUPM_UNLABEL_IDS" ]]; then
  _bupm_ids=()
  for _bupm_id in $BUPM_UNLABEL_IDS; do _bupm_ids+=(-f "ids[]=$_bupm_id"); done
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  if command -v gh >/dev/null 2>&1 &&
    _bupm_api graphql -f query='query($ids:[ID!]!){nodes(ids:$ids){... on Label{name}}}' "${_bupm_ids[@]}" \
      --jq '[.data.nodes[]? | .name? // empty | ascii_downcase] | index("pr-verify-failed") != null'; then
    [[ "$BUPM_OUT" == true ]] && BUPM_UNLABEL=1
  else
    _bupm_msg="guardrails merge-guard: could not read which labels this removeLabelsFromLabelable removes (${BUPM_ERR:-gh is not on PATH}), so it runs unchecked. Never remove pr-verify-failed: only a PASS verdict at a newer head clears it."
    hook::emit_channels PreToolUse "$_bupm_msg" "$_bupm_msg"
  fi
fi
((BUPM_UNLABEL_GQL)) &&
  _bupm_block pr-verify-label-removal-unresolvable \
    'BLOCKED: this removeLabelsFromLabelable names no literal LA_ label id, so guardrails cannot tell whether it removes the pr-verify-failed label.' \
    'Fix: pass each label id as a literal LA_... id, or use gh pr edit <number> --remove-label <name>.'
if ((BUPM_UNLABEL)) || { ((BUPM_UNLABEL_VAR)) && [[ "${_bupm_bare-}" == *pr-verify-failed* ]]; }; then
  _bupm_block pr-verify-label-removal \
    'BLOCKED: this command removes the pr-verify-failed label, which is pr-verify'"'"'s FAIL hold on the pull request.' \
    'Only a PASS verdict at a newer head clears it, and pr-verify'"'"'s own workflow removes it then. Fix what the FAIL comment names, push, and let pr-verify judge the new head.'
fi
[[ -n "$BUPM_FORM" ]] || exit 0

((BUPM_BT)) &&
  _bupm_refuse_target "the command holds a backtick, and a backtick substitution can change or hide the target; remove every backtick, and pass a body that holds one with --body-file"
((BUPM_CONT)) &&
  _bupm_refuse_target "the command continues a line with a backslash, which can join or split the merge differently from how the guard reads it; write the merge on one line"
((BUPM_MERGES > 1)) &&
  _bupm_refuse_target "this command holds $BUPM_MERGES merges and only one can be checked; run each merge as its own command"
[[ -z "$BUPM_UNRESOLVED" ]] || _bupm_refuse_target "$BUPM_UNRESOLVED"
if [[ "$BUPM_FORM" == gh-pr-merge && -z "$BUPM_REPO" && ! "$BUPM_SEL" =~ ^https?:// ]]; then
  ((BUPM_CD)) &&
    _bupm_refuse_target "the command changes directory before the merge and names no -R repository, so the merge may not run in the session's repository"
  ((BUPM_GHREPO)) &&
    _bupm_refuse_target "the command names GH_REPO or GH_HOST and no -R repository, so the merge may not run in the session's repository"
fi

if [[ "$BUPM_FORM" == graphql ]]; then
  [[ -n "$BUPM_NODE" ]] || _bupm_refuse "the mutation's pull request id is not a literal PR_ node id in the command"
fi
command -v gh >/dev/null 2>&1 || _bupm_unchecked "gh is not on PATH"

[[ -n "$BUPM_REPO" ]] || BUPM_REPO="{owner}/{repo}"

if [[ "$BUPM_REPO" =~ ^([^/]+)/([^/]+/[^/]+)$ ]]; then
  BUPM_REPO="${BASH_REMATCH[2]}"
  [[ "${BASH_REMATCH[1],,}" == github.com ]] || BUPM_HOST="${BASH_REMATCH[1]}"
fi

_bupm_pr_unreadable() {
  if [[ "$BUPM_ERR" == *"HTTP 404"* && "$BUPM_REPO" != *'{'* ]]; then
    _bupm_refuse_target "GitHub answered HTTP 404 for ${BUPM_REPO}${BUPM_NUM:+#$BUPM_NUM}, so the guard cannot tell which pull request this merge targets"
  fi
  _bupm_unchecked "$BUPM_ERR"
}

if [[ "$BUPM_FORM" == graphql ]]; then
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  _bupm_api graphql -f query='query($id:ID!){node(id:$id){... on PullRequest{number repository{nameWithOwner}}}}' \
    -f id="$BUPM_NODE" --jq '.data.node | "\(.repository.nameWithOwner) \(.number)"' || {
    [[ "$BUPM_ERR" =~ (Bad\ credentials|HTTP\ 401|gh\ auth\ login|not\ logged\ in) ]] &&
      _bupm_unchecked "node $BUPM_NODE: $BUPM_ERR"
    _bupm_refuse "node $BUPM_NODE could not be read: $BUPM_ERR"
  }
  read -r BUPM_REPO BUPM_NUM <<<"$BUPM_OUT"
  [[ "$BUPM_NUM" =~ ^[0-9]+$ ]] || _bupm_refuse "node $BUPM_NODE is not a pull request"
fi

if [[ "$BUPM_FORM" == gh-pr-merge ]]; then
  _bupm_branch=""
  if [[ "$BUPM_SEL" =~ ^#?([0-9]+)$ ]]; then
    BUPM_NUM="${BASH_REMATCH[1]}"
  elif [[ "$BUPM_SEL" =~ ^https?://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
    BUPM_REPO="${BASH_REMATCH[2]}"
    BUPM_NUM="${BASH_REMATCH[3]}"
    BUPM_HOST=""
    [[ "${BASH_REMATCH[1],,}" == github.com ]] || BUPM_HOST="${BASH_REMATCH[1]}"
  elif [[ -n "$BUPM_SEL" ]]; then
    _bupm_branch="$BUPM_SEL"
  else
    _bupm_branch=$(hook::git_untrusted -C "${BUPM_CWD:-.}" branch --show-current 2>/dev/null) || _bupm_branch=""
    [[ -n "$_bupm_branch" ]] || _bupm_refuse_target "no PR was named and the current branch could not be read"
  fi
  if [[ -z "$BUPM_NUM" ]]; then
    _bupm_urlencode _bupm_head "$_bupm_branch"
    [[ "$_bupm_branch" == *:* ]] || _bupm_head="${BUPM_REPO%%/*}:$_bupm_head"
    _bupm_api "repos/$BUPM_REPO/pulls?state=open&head=$_bupm_head" --jq '.[0].number // empty' ||
      _bupm_pr_unreadable
    BUPM_NUM="$BUPM_OUT"
    [[ "$BUPM_NUM" =~ ^[0-9]+$ ]] || _bupm_refuse_target "no open pull request found for branch $_bupm_head; for a fork's branch write <fork-owner>:<branch> or the PR number"
  fi
fi

[[ "$BUPM_NUM" =~ ^[0-9]+$ ]] || _bupm_unchecked "the pull request number could not be read"

_mg_unchecked() {
  BUPM_REPO="$MG_REPO"
  _bupm_unchecked "$@"
}
_mg_pr_unreadable() {
  BUPM_ERR="$MG_ERR"
  _bupm_pr_unreadable
}
_mg_refuse_merge() {
  local kind="$1"
  shift
  [[ "$kind" == closed ]] && exit 0
  [[ "$kind" == not-ready ]] && kind=""
  _bupm_block "$BUPM_FORM${kind:+-$kind}" "$@" \
    'Merge through /source-control:pull-request merge, which runs this same readiness check and waits for what is pending.'
}
_mg_allow() {
  if (($#)); then
    _bupm_msg="guardrails merge-guard: ${MG_REPO}#${MG_NUM} is allowed to merge. $*"
    hook::emit_channels PreToolUse "$_bupm_msg" "$_bupm_msg"
    emit_tel "warned" "$BUPM_FORM"
  else
    emit_tel "ok" "$BUPM_FORM"
  fi
  exit 0
}

MG_REPO="$BUPM_REPO" MG_NUM="$BUPM_NUM" MG_HOST="$BUPM_HOST" MG_CWD="$BUPM_CWD" MG_AUTO="$BUPM_AUTO" MG_HEAD=""
merge_readiness::check
