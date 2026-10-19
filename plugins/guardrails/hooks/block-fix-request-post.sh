#!/usr/bin/env bash
# PreToolUse hook: block an agent from posting the PR-fix lane's fix request.
#
# WHY. The address-feedback lane (.github/scripts/pr-unblock/address-feedback.mjs,
# FIX_REQUEST) treats a comment line that starts with
# `PR-fix lane: please fix this finding` (any case), written by a trusted person
# with write access, as direction for a lane that holds push credentials. A
# local session posts with the owner's GitHub token, so a prompt-injected agent
# could steer that lane. The owner decided that only they, typing in the GitHub
# UI, post the phrase (#8438). This guard holds that decision on the Bash and
# PowerShell tools and on the GitHub MCP server's comment, review, issue and
# pull-request write tools.
#
# WHAT BLOCKS. A command that posts or edits GitHub content, carrying the phrase
# where the lane would read it as a request:
#   gh          `gh pr|issue comment|review|create|edit` (`--body`, `--body-file`,
#               `-F`, `-` for stdin); `gh api` that writes (a field, `--input`,
#               or a method other than GET or HEAD), reading `-F k=@file`,
#               `--input file` and `@-`/`-` from stdin.
#   curl        to api.github.com or a GHES `/api/v3` or `/api/graphql` route,
#               with a data, form or upload flag and no `-G`; `@file` and `@-`
#               are read.
#   GraphQL     through either, only when the query text names a mutation.
#   MCP         the tool's `body`, and a review's `comments`.
# The body is read from the posting command's own words (a quoted
# `$(cat <<EOF ...)` stays in its word, and a quoted `$(cat file)` is read) and
# every file it names as a body. When a posting command reads stdin or expands
# a variable or substitution, when the command redirects into a body file it
# posts or names one that does not exist yet, or on PowerShell, the whole
# command text (heredocs, pipes, assignments), here-strings and every file fed
# through `cat` or `<` are read too. Relative paths resolve against the
# payload's cwd. A `bash -c`/`sh -c` operand and an `eval` are read as commands
# too.
#
# HOW A BODY IS READ. Case-insensitively, as FIX_REQUEST is, and line by line:
# a line counts when the phrase starts it, or follows a quote or `=` that opens
# a value (`--body "PR-fix ...`, `"body":"PR-fix ...`, `body=PR-fix ...`), and
# is not followed by a letter, digit or `_`. JSON (`\n`, `\u000a`) and URL
# (`%0A`, `+`) escapes are decoded first. A line inside a fence does not count,
# with the lane's own fence rule (a line starting with up to three spaces and
# ``` or ~~~, either marker toggling it), so the guard never sees a fence the
# lane does not; nor does a
# line starting `>`, nor a mention later in a line. Doubt resolves to a block:
# the phrase inside an HTML comment counts, as it does for the lane, and so
# does a quoted mention mid-line (`see "PR-fix lane: please fix this finding"`).
# A false block costs a rephrase; a missed one steers a push-holding lane.
#
# STAYS QUIET on a command that reads, greps or shows the phrase (`grep`,
# `git show`, `gh search`, a `gh api` GET, a GraphQL query), on a command that
# posts nothing to GitHub, and on Write and Edit, which are not wired to it.
#
# KNOWN GAPS: a body assembled through a variable, `printf` with a computed
# argument or another expansion; a script (Python, Node) or cmdlet
# (`Invoke-RestMethod`) that posts; a wrapper this guard does not step over
# (`xargs`, `sudo` with an option other than -u/-g/-C/-D); a relative body
# file after a `cd` in the same command, which resolves against the payload's
# cwd instead; a body file another program writes or copies in the same
# command (`cp`, a script) with no redirect; a body file past 1 MiB is read to
# that point only.
#
# Escape: the `block_fix_request_post_enabled` userConfig option (true or false;
# any other value keeps the guard on and says so). userConfig resolves at
# plugin-enable time, so an inline env prefix on the command cannot change it.
#
# BLOCKING: exits 2 on a detected post.

set -uo pipefail

# Kill switch FIRST, above every source (scripts/check-killswitch-hoist.sh).
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED:-true}" == "false" ]] && exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a dual-channel "guard did not run"
# notice; 0 (allow) and 2 (block) pass through, like the other per-call guards.
guard::abort_boundary block-fix-request-post PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

_bfr_enabled="${CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED:-true}"
start=${EPOCHREALTIME:-}

# rc 1 (empty stdin) skips; rc 2 (not JSON) FAILS CLOSED; rc 3 (a payload cut
# short by the pipe) is a loud skip the dispatcher takes once.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
[[ "$_bfr_enabled" == true ]] ||
  guard::bad_switch_notice block_fix_request_post_enabled "$_bfr_enabled" "$INPUT"

hook::require_jq_blocking "guardrails-block-fix-request-post" "block_fix_request_post_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || jq_rc=$?
if ((jq_rc == 2)); then
  guard::refuse_unparsable
  exit 2
fi
((jq_rc != 0)) && exit 0
if ((HOOK_JQ_FIELDS_NUL)); then
  guard::refuse_nul
  exit 2
fi
COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
_BFR_CWD="${HOOK_JQ_FIELDS[2]:-$PWD}"

_BFR_PHRASE='pr-fix lane: please fix this finding'
# A request line: the phrase at a line start or right after a value-opening
# quote or `=`, then no word character. The fast form reads the whole text, a
# newline standing for the line start; the line form is for fenced text.
_bfr_q="[\"'=]"
_BFR_RE_ANY="(["$'\n'"\"'=])${_BFR_PHRASE}([^[:alnum:]_]|\$)"
_BFR_RE_LINE="^(.*${_bfr_q})?${_BFR_PHRASE}([^[:alnum:]_]|\$)"
_BFR_RE_FENCE="^ {0,3}(\`\`\`|~~~)"
# A 1 MiB read covers a comment body.
_BFR_MAX_READ=1048576

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$2"
  hook::emit_telemetry "block-fix-request-post" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  printf '%s\n' \
    "BLOCKED: this would post the PR-fix lane fix request (a line starting \"PR-fix lane: please fix this finding\") to GitHub ($1)." \
    "Only the repository owner may post a fix request, typed in the GitHub UI: the address-feedback lane acts on it with push credentials, and an agent posts with the owner's token (owner decision, https://github.com/melodic-software/claude-code-plugins/issues/8438)." \
    "Leave the request to the owner. To cite the phrase, put it after \"> \" or inside a code fence." >&2
  emit_tel blocked "$1"
  exit 2
}

# _bfr_lines <lowercased text>: 0 when a line reads as a fix request.
_bfr_lines() {
  [[ "$1" == *"$_BFR_PHRASE"* ]] || return 1
  if [[ "$1" != *'```'* && "$1" != *'~~~'* ]]; then
    [[ $'\n'"$1" =~ $_BFR_RE_ANY ]]
    return
  fi
  local line fenced=0
  local -a lines=()
  mapfile -t lines <<<"$1"
  for line in "${lines[@]}"; do
    if [[ "$line" =~ $_BFR_RE_FENCE ]]; then
      fenced=$((1 - fenced))
    elif ((! fenced)) && [[ "$line" =~ $_BFR_RE_LINE ]]; then
      return 0
    fi
  done
  return 1
}

# _bfr_carries <text>: 0 when <text>, or its JSON- or URL-decoded form, holds a
# request line.
# shellcheck disable=SC1003  # '\' compares a literal backslash, not a quote escape
_bfr_carries() {
  local t="${1,,}" d
  t="${t//$'\r'/}"
  _bfr_lines "$t" && return 0
  if [[ "$t" == *'\'* ]]; then
    d="${t//\\r/}"
    d="${d//\\n/$'\n'}"
    d="${d//\\u000a/$'\n'}"
    d="${d//\\u000d/}"
    d="${d//\\u0020/ }"
    d="${d//\\u002d/-}"
    d="${d//\\u003a/:}"
    d="${d//\\t/$'\t'}"
    d="${d//\\\"/\"}"
    d="${d//\\\'/\'}"
    d="${d//\\ / }"
    _bfr_lines "$d" && return 0
  fi
  if [[ "$t" == *%* || "$t" == *+* ]]; then
    d="${t//%0d/}"
    d="${d//%0a/$'\n'}"
    d="${d//+/ }"
    d="${d//%20/ }"
    d="${d//%2d/-}"
    d="${d//%3a/:}"
    d="${d//%22/\"}"
    d="${d//%27/\'}"
    d="${d//%3d/=}"
    _bfr_lines "$d" && return 0
  fi
  return 1
}

# _bfr_read_to <dest> <path>: the file's first _BFR_MAX_READ characters;
# 1 when it is stdin, missing or unreadable.
_bfr_read_to() {
  local -n __bfr_dest="$1"
  local p="$2"
  __bfr_dest=""
  case "$p" in
  - | /dev/stdin | /dev/fd/0) return 1 ;;
  \~) p="$HOME" ;;
  \~/*) p="$HOME/${p#\~/}" ;;
  /* | [A-Za-z]:[\\/]*) ;;
  *) p="$_BFR_CWD/$p" ;;
  esac
  [[ -f "$p" && -r "$p" ]] || return 1
  IFS= read -r -N "$_BFR_MAX_READ" __bfr_dest <"$p"
  return 0
}

# What the parse collects. A command posts when one segment posts; then every
# collected text and file is read.
_BFR_POST=""      # the form of the first posting segment
_BFR_TEXTS=()     # words of posting segments
_BFR_FILES=()     # body files of posting segments
_BFR_STDIN=0      # a posting segment reads stdin
_BFR_SUBST=0      # a posting word expands something (`$`, or a split `$(`)
_BFR_WRITES=0     # the command writes a body file before posting it
_BFR_WTARGETS=()  # files the command redirects output to
_BFR_AUX_TEXTS=() # here-strings, read only when the whole command is
_BFR_AUX_FILES=() # `cat` operands and `<` targets, likewise

# _bfr_file_operand <value>: record a body file, or stdin for `-`.
# shellcheck disable=SC2329  # reached from the parse callback
_bfr_file_operand() {
  case "$1" in
  - | /dev/stdin | /dev/fd/0) _BFR_STDIN=1 ;;
  ?*) _BFR_FILES+=("$1") ;;
  *) ;;
  esac
}

# _bfr_at_operand <value>: `@file` (gh -F, curl -d) names a file.
# shellcheck disable=SC2329  # reached from the parse callback
_bfr_at_operand() {
  [[ "$1" == @* ]] && _bfr_file_operand "${1#@}"
  return 0
}

# _bfr_is_mutation <text>... plus the files recorded since <mark>: GraphQL
# writes only through a mutation.
# shellcheck disable=SC2329  # reached from the parse callback
_bfr_is_mutation() {
  local mark="$1" t f c
  shift
  for t in "$@"; do
    [[ "${t,,}" == *mutation* ]] && return 0
  done
  for f in ${_BFR_FILES[@]+"${_BFR_FILES[@]:mark}"}; do
    _bfr_read_to c "$f" && [[ "${c,,}" == *mutation* ]] && return 0
  done
  ((_BFR_STDIN)) && [[ "${COMMAND,,}" == *mutation* ]]
}

# gh pr|issue <action> <args>
# shellcheck disable=SC2329  # reached from the parse callback
_bfr_gh_body() {
  local a
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    -F | --body-file) _bfr_file_operand "${1-}" && shift ;;
    --body-file=*) _bfr_file_operand "${a#--body-file=}" ;;
    -F?*) _bfr_file_operand "${a#-F}" ;;
    *) ;;
    esac
  done
}

# gh api <args>: 0 when it writes.
# shellcheck disable=SC2329  # reached from the parse callback
_bfr_gh_api() {
  local a v method="" endpoint="" writes=0 mark=${#_BFR_FILES[@]} stdin0=$_BFR_STDIN
  local -a vals=()
  while (($#)); do
    a="$1"
    shift
    v=""
    case "$a" in
    -X | --method) method="${1-}" && shift && continue ;;
    --method=*) method="${a#--method=}" && continue ;;
    -X?*) method="${a#-X}" && continue ;;
    -F | --field) v="${1-}" && shift ;;
    --field=*) v="${a#--field=}" ;;
    -F?*) v="${a#-F}" ;;
    -f | --raw-field)
      vals+=("${1-}")
      shift
      writes=1
      continue
      ;;
    --raw-field=*) vals+=("${a#--raw-field=}") && writes=1 && continue ;;
    -f?*) vals+=("${a#-f}") && writes=1 && continue ;;
    --input)
      _bfr_file_operand "${1-}"
      shift
      writes=1
      continue
      ;;
    --input=*) _bfr_file_operand "${a#--input=}" && writes=1 && continue ;;
    -H | --header | -q | --jq | -t | --template | --hostname | --cache | -p | --preview) shift && continue ;;
    -*) continue ;;
    *)
      [[ -z "$endpoint" ]] && endpoint="$a"
      continue
      ;;
    esac
    writes=1
    vals+=("$v")
    _bfr_at_operand "${v#*=}"
  done
  method="${method^^}"
  if [[ -n "$method" ]]; then
    [[ "$method" != GET && "$method" != HEAD ]] && writes=1
    [[ "$method" == GET || "$method" == HEAD ]] && writes=0
  fi
  if ((writes)) && [[ "${endpoint#/}" == graphql ]]; then
    _bfr_is_mutation "$mark" ${vals[@]+"${vals[@]}"} || writes=0
  fi
  if ((! writes)); then
    _BFR_FILES=("${_BFR_FILES[@]:0:mark}")
    _BFR_STDIN=$stdin0
    return 1
  fi
  return 0
}

# curl <args>: 0 when it sends data to a GitHub API route.
# shellcheck disable=SC2329  # reached from the parse callback
_bfr_curl() {
  local a v github=0 graphql=0 data=0 get=0 mark=${#_BFR_FILES[@]} stdin0=$_BFR_STDIN
  local -a vals=()
  local re_gh='(^|[/.@])api\.github\.com|/api/v3(/|$)|/api/graphql'
  while (($#)); do
    a="$1"
    shift
    v=""
    case "$a" in
    -d | --data | --data-ascii | --data-binary | --json | --data-urlencode) v="${1-}" && shift ;;
    --data=* | --data-ascii=* | --data-binary=* | --json=* | --data-urlencode=*) v="${a#*=}" ;;
    -d?*) v="${a#-d}" ;;
    --data-raw | --form-string) vals+=("${1-}") && shift && data=1 && continue ;;
    --data-raw=* | --form-string=*) vals+=("${a#*=}") && data=1 && continue ;;
    -F | --form)
      v="${1-}"
      shift
      vals+=("$v")
      data=1
      v="${v#*=}"
      [[ "$v" == '<'* ]] && v="@${v#<}"
      _bfr_at_operand "${v%%;*}"
      continue
      ;;
    -T | --upload-file) _bfr_file_operand "${1-}" && shift && data=1 && continue ;;
    --upload-file=*) _bfr_file_operand "${a#*=}" && data=1 && continue ;;
    -G | --get) get=1 && continue ;;
    *)
      [[ "$a" =~ $re_gh ]] && github=1
      [[ "$a" == */graphql* ]] && graphql=1
      continue
      ;;
    esac
    data=1
    vals+=("$v")
    # --data-urlencode takes `name@file` as well as `@file`.
    [[ "$v" != @* && "$v" =~ ^[^=@]*@ ]] && v="@${v#*@}"
    _bfr_at_operand "$v"
  done
  if ((github && data && ! get)) && { ((! graphql)) || _bfr_is_mutation "$mark" ${vals[@]+"${vals[@]}"}; }; then
    return 0
  fi
  _BFR_FILES=("${_BFR_FILES[@]:0:mark}")
  _BFR_STDIN=$stdin0
  return 1
}

# hook::bash_parse_segments callback: one segment's argv words.
# shellcheck disable=SC2329  # invoked through hook::bash_parse_segments
_bfr_segment() {
  local j cmd form=""
  # What stdin and here-strings feed this segment: read only when it posts,
  # which is judged after the whole parse, so record them now.
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    ((${HOOK_SEG_REDIR_OPAQUE[j]:-0})) && continue
    case "${HOOK_SEG_REDIR_OP[j]}" in
    '<') _BFR_AUX_FILES+=("${HOOK_SEG_REDIR_TARGET[j]}") ;;
    '>' | '>>' | '>|' | '<>') _BFR_WTARGETS+=("${HOOK_SEG_REDIR_TARGET[j]}") ;;
    '<<<') _BFR_AUX_TEXTS+=("${HOOK_SEG_REDIR_TARGET[j]}") ;;
    *) ;;
    esac
  done
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" _bfr_segment
    return 0
  fi
  # Step over what stands before the command word: assignments, a reserved
  # word the tokenizer leaves at a segment head, and launchers with flags.
  while (($#)); do
    case "$1" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until | command | builtin | time | exec | nohup | sudo | doas | env | nice | timeout | --) shift ;;
    -u | -g | -C | -D)
      shift
      (($#)) && shift
      ;;
    -* | [0-9]*) shift ;;
    *)
      [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || break
      shift
      ;;
    esac
  done
  (($#)) || return 0
  cmd="${1##*/}"
  cmd="${cmd##*\\}"
  cmd="${cmd,,}"
  cmd="${cmd%.exe}"
  shift
  case "$cmd" in
  eval)
    hook::bash_parse_segments "$*" _bfr_segment
    return 0
    ;;
  cat | type | get-content | gc)
    for j in "$@"; do
      [[ "$j" == -* ]] || _BFR_AUX_FILES+=("$j")
    done
    return 0
    ;;
  gh)
    case "${1-}" in
    pr | issue)
      local group="$1"
      shift
      while [[ "${1-}" == -R || "${1-}" == --repo ]]; do
        shift
        (($#)) && shift
      done
      [[ "${1-}" == --repo=* || "${1-}" == -R?* ]] && shift
      case "${1-}" in
      comment | review | create | edit)
        form="gh-$group-$1"
        _bfr_gh_body "${@:2}"
        ;;
      *) ;;
      esac
      ;;
    api) _bfr_gh_api "${@:2}" && form="gh-api" ;;
    *) ;;
    esac
    ;;
  curl) _bfr_curl "$@" && form="curl" ;;
  *) ;;
  esac
  [[ -n "$form" ]] || return 0
  [[ -n "$_BFR_POST" ]] || _BFR_POST="$form"
  local w rest
  _BFR_TEXTS+=("$@")
  # A variable or substitution brings its text from elsewhere in the command
  # (`B=...; gh ... --body "$B"`); an unquoted `$(` splits the segment and
  # leaves a word ending in `$`.
  for w in "$@"; do
    [[ "$w" == *'$'* ]] && _BFR_SUBST=1
  done
  # A quoted `$(cat file)` or `$(<file)` stays inside its word, unparsed.
  # shellcheck disable=SC2016  # a regex: `$(` is matched, not expanded
  local re_sub='(\$\(|`)(cat[[:space:]]+|<[[:space:]]*)([^)`]*)'
  for w in "$@"; do
    rest="$w"
    while [[ "$rest" =~ $re_sub ]]; do
      rest="${rest#*"${BASH_REMATCH[0]}"}"
      for j in ${BASH_REMATCH[3]}; do
        [[ "$j" == -* ]] || _BFR_FILES+=("${j//[\"\']/}")
      done
    done
  done
  return 0
}

# --- the GitHub MCP server's write tools ------------------------------------
if [[ "$TOOL_NAME" == mcp__* ]]; then
  # hooks.json names the tools; any other MCP payload that reaches here has no
  # body to post.
  jq_rc=0
  hook::jq_fields "$INPUT" '.tool_input.body' '.tool_input.comments' || jq_rc=$?
  if ((jq_rc == 2)); then
    guard::refuse_unparsable
    exit 2
  fi
  ((jq_rc != 0)) && exit 0
  if ((HOOK_JQ_FIELDS_NUL)); then
    guard::refuse_nul
    exit 2
  fi
  for _bfr_t in "${HOOK_JQ_FIELDS[@]}"; do
    _bfr_carries "$_bfr_t" && block "${TOOL_NAME##*__}"
  done
  emit_tel ok ""
  exit 0
fi

[[ -n "$COMMAND" ]] || exit 0
_bfr_lc="${COMMAND,,}"
# Past the row's shared ceiling the command is not parsed; one that names the
# phrase is refused unread.
MAX_COMMAND_LEN=16384
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  [[ "$_bfr_lc" == *"$_BFR_PHRASE"* ]] && block "too-long"
  exit 0
fi
# Cheap pre-filter: a post names the phrase (quotes and escapes aside), or names
# gh or curl with a way to read a body from elsewhere.
_bfr_flat="${_bfr_lc//[\\\'\"]/}"
if [[ "$_bfr_flat" != *"pr-fix lane"* && "$_bfr_flat" != *pr-fix%20lane* && "$_bfr_flat" != *pr-fix+lane* ]]; then
  _bfr_re_cli='(^|[^a-z0-9_.-])(gh|curl)(\.exe)?([^a-z0-9_-]|$)'
  [[ "$_bfr_lc" =~ $_bfr_re_cli ]] || exit 0
  [[ "$_bfr_lc" == *@* || "$_bfr_lc" == *-f* || "$_bfr_lc" == *--input* || "$_bfr_lc" == *'<'* || "$_bfr_lc" == *cat* ]] || exit 0
fi

hook::bash_parse_segments "$COMMAND" _bfr_segment
if [[ -z "$_BFR_POST" ]]; then
  emit_tel ok ""
  exit 0
fi

# The body may sit anywhere in the command when a posting command reads
# stdin or expands a variable or substitution, when the command redirects
# into a body file it posts (`printf ... > b.md && gh pr comment 1 -F b.md`),
# when a body file does not exist yet, or on PowerShell (whose quoting the bash tokenizer only
# approximates): then read all of it. A backtick may open a substitution too,
# but ``` in a fenced body is one as well, so it adds only the files `cat` and
# `<` name. Otherwise only the posting command's words and files are read, so
# a grep of the phrase beside an unrelated post stays quiet.
_bfr_c=""
for _bfr_f in ${_BFR_FILES[@]+"${_BFR_FILES[@]}"}; do
  # A body file the command itself redirects into holds what the command
  # writes, not what is on disk now. Matched by name, so doubt reads more.
  for _bfr_t in ${_BFR_WTARGETS[@]+"${_BFR_WTARGETS[@]}"}; do
    [[ "${_bfr_t##*/}" == "${_bfr_f##*/}" ]] && _BFR_WRITES=1
  done
  if _bfr_read_to _bfr_c "$_bfr_f"; then
    _bfr_carries "$_bfr_c" && block "$_BFR_POST, from $_bfr_f"
  else
    _BFR_WRITES=1
  fi
done
_BFR_FILES=()
if ((_BFR_STDIN || _BFR_SUBST || _BFR_WRITES)) || [[ "$TOOL_NAME" == PowerShell ]]; then
  _bfr_carries "$COMMAND" && block "$_BFR_POST"
  _BFR_TEXTS+=(${_BFR_AUX_TEXTS[@]+"${_BFR_AUX_TEXTS[@]}"})
  _BFR_FILES+=(${_BFR_AUX_FILES[@]+"${_BFR_AUX_FILES[@]}"})
elif [[ "$COMMAND" == *'`'* ]]; then
  _BFR_FILES+=(${_BFR_AUX_FILES[@]+"${_BFR_AUX_FILES[@]}"})
fi
for _bfr_t in ${_BFR_TEXTS[@]+"${_BFR_TEXTS[@]}"}; do
  _bfr_carries "$_bfr_t" && block "$_BFR_POST"
done
for _bfr_f in ${_BFR_FILES[@]+"${_BFR_FILES[@]}"}; do
  _bfr_read_to _bfr_c "$_bfr_f" && _bfr_carries "$_bfr_c" && block "$_BFR_POST, from $_bfr_f"
done
emit_tel ok ""
exit 0
