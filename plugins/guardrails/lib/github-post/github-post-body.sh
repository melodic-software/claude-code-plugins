# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # GHPOST_* results are read by the sourcing guard; HOOK_* globals come from hook-utils.sh
# What a Bash or PowerShell command posts to GitHub: the body text a
# `gh pr|issue comment|review|create|edit`, a writing `gh api`, or a `curl` with
# data to a GitHub API route carries. Shared by block-fix-request-post and
# block-github-post-content, so both read the same bodies.
#
# A library, not executable: needs hook-utils.sh (hook::bash_parse_segments,
# hook::shell_c_operand) loaded first. Callers judge the text; this file only
# finds it.
#
# Call as:
#   ghpost::collect <command> <cwd> <tool name>
#     Parses <command>. GHPOST_POST is the form of the first posting segment
#     (`gh-pr-comment`, `gh-api`, `curl`), empty when nothing posts.
#   ghpost::bodies
#     After a collect that found a post: fills GHPOST_BODY (texts),
#     GHPOST_BODY_SRC (the file a text was read from, else "") and
#     GHPOST_BODY_KIND (`file` a body file's content, `command` the whole
#     command, `word` a posting segment's word, `aux` a here-string or a file
#     fed through `cat` or `<`), in the order a caller should judge them.
#     GHPOST_PATHS lists every file path the command names, so a caller can
#     drop those operands from the words it judges.
#
# WHAT IS READ. The posting command's own words (a quoted `$(cat <<EOF ...)`
# stays in its word, and a quoted `$(cat file)` is read) and every file it
# names as a body: `--body-file`, `-F`, `-` for stdin; `gh api` fields,
# `-F k=@file`, `--input file`; curl data, form and upload flags, `@file` and
# `@-`. When a posting command reads stdin or expands a variable or
# substitution, when it posts a body file and the command writes a file or the
# body file does not exist yet, or on PowerShell, the whole command text,
# here-strings and every file fed through `cat` or `<` are read too. Relative
# paths resolve against <cwd>. A `bash -c`/`sh -c` operand and an `eval` are
# read as commands, and so is the command after `--` in a script wrapper
# (`bash gate.sh run KEY -- CMD +++ CMD`, `./wrap.sh ... -- CMD`), split on
# bare `+++` words.
#
# GraphQL counts as a write only when the query text names a mutation.

[[ -n "${_GUARDRAILS_GHPOST_LOADED:-}" ]] && return 0
_GUARDRAILS_GHPOST_LOADED=1

# A 1 MiB read covers a comment body.
GHPOST_MAX_READ=1048576

# ghpost::read_to <dest> <path>: the file's first GHPOST_MAX_READ characters;
# 1 when it is stdin, missing or unreadable.
ghpost::read_to() {
  local -n __ghp_dest="$1"
  local p="$2"
  __ghp_dest=""
  case "$p" in
  - | /dev/stdin | /dev/fd/0) return 1 ;;
  \~) p="$HOME" ;;
  \~/*) p="$HOME/${p#\~/}" ;;
  /* | [A-Za-z]:[\\/]*) ;;
  *) p="$GHPOST_CWD/$p" ;;
  esac
  [[ -f "$p" && -r "$p" ]] || return 1
  IFS= read -r -N "$GHPOST_MAX_READ" __ghp_dest <"$p"
  return 0
}

# ghpost::reset: clear what a parse collects.
ghpost::reset() {
  GHPOST_POST=""      # the form of the first posting segment
  GHPOST_TEXTS=()     # words of posting segments
  GHPOST_FILES=()     # body files of posting segments
  GHPOST_STDIN=0      # a posting segment reads stdin
  GHPOST_SUBST=0      # a posting word expands something (`$`, or a split `$(`)
  GHPOST_WRITES=0     # the command writes a body file before posting it
  GHPOST_WTARGETS=()  # files the command writes: redirects, and cp/mv/ln/tee runs
  GHPOST_AUX_TEXTS=() # here-strings, read only when the whole command is
  GHPOST_AUX_FILES=() # `cat` operands and `<` targets, likewise
  GHPOST_BODY=()
  GHPOST_BODY_SRC=()
  GHPOST_BODY_KIND=()
  GHPOST_PATHS=()
}

# ghpost::file_operand <value>: record a body file, or stdin for `-`.
ghpost::file_operand() {
  case "$1" in
  - | /dev/stdin | /dev/fd/0) GHPOST_STDIN=1 ;;
  ?*) GHPOST_FILES+=("$1") ;;
  *) ;;
  esac
}

# ghpost::at_operand <value>: `@file` (gh -F, curl -d) names a file.
ghpost::at_operand() {
  [[ "$1" == @* ]] && ghpost::file_operand "${1#@}"
  return 0
}

# ghpost::is_mutation <mark> <text>... plus the files recorded since <mark>:
# GraphQL writes only through a mutation.
ghpost::is_mutation() {
  local mark="$1" t f c
  shift
  for t in "$@"; do
    [[ "${t,,}" == *mutation* ]] && return 0
  done
  for f in ${GHPOST_FILES[@]+"${GHPOST_FILES[@]:mark}"}; do
    ghpost::read_to c "$f" && [[ "${c,,}" == *mutation* ]] && return 0
  done
  ((GHPOST_STDIN)) && [[ "${GHPOST_COMMAND,,}" == *mutation* ]]
}

# gh pr|issue <action> <args>
ghpost::gh_body() {
  local a
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    -F | --body-file) ghpost::file_operand "${1-}" && shift ;;
    --body-file=*) ghpost::file_operand "${a#--body-file=}" ;;
    -F?*) ghpost::file_operand "${a#-F}" ;;
    *) ;;
    esac
  done
}

# gh api <args>: 0 when it writes.
ghpost::gh_api() {
  local a v method="" endpoint="" writes=0 mark=${#GHPOST_FILES[@]} stdin0=$GHPOST_STDIN
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
      ghpost::file_operand "${1-}"
      shift
      writes=1
      continue
      ;;
    --input=*) ghpost::file_operand "${a#--input=}" && writes=1 && continue ;;
    -H | --header | -q | --jq | -t | --template | --hostname | --cache | -p | --preview) shift && continue ;;
    -*) continue ;;
    *)
      [[ -z "$endpoint" ]] && endpoint="$a"
      continue
      ;;
    esac
    writes=1
    vals+=("$v")
    ghpost::at_operand "${v#*=}"
  done
  method="${method^^}"
  if [[ -n "$method" ]]; then
    [[ "$method" != GET && "$method" != HEAD ]] && writes=1
    [[ "$method" == GET || "$method" == HEAD ]] && writes=0
  fi
  if ((writes)) && [[ "${endpoint#/}" == graphql ]]; then
    ghpost::is_mutation "$mark" ${vals[@]+"${vals[@]}"} || writes=0
  fi
  if ((!writes)); then
    GHPOST_FILES=("${GHPOST_FILES[@]:0:mark}")
    GHPOST_STDIN=$stdin0
    return 1
  fi
  return 0
}

# curl <args>: 0 when it sends data to a GitHub API route.
ghpost::curl() {
  local a v github=0 graphql=0 data=0 get=0 mark=${#GHPOST_FILES[@]} stdin0=$GHPOST_STDIN
  local -a vals=()
  local re_gh='(^|[/.@])api\.github\.com|/api/v3(/|$)|/api/graphql'
  while (($#)); do
    a="$1"
    shift
    v=""
    # Short flags written together (`-sSd X`, `-sGd X`): a `G` among them is
    # -G, and the first of `d`, `F` or `T` takes the rest as that flag.
    if [[ "$a" =~ ^-[A-Za-z]{2,}$ ]]; then
      local k
      for ((k = 1; k < ${#a}; k++)); do
        case "${a:k:1}" in
        G) get=1 ;;
        d | F | T)
          a="-${a:k}"
          break
          ;;
        *) ;;
        esac
      done
    fi
    case "$a" in
    -d | --data | --data-ascii | --data-binary | --json | --data-urlencode | --expand-data) v="${1-}" && shift ;;
    --data=* | --data-ascii=* | --data-binary=* | --json=* | --data-urlencode=* | --expand-data=*) v="${a#*=}" ;;
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
      ghpost::at_operand "${v%%;*}"
      continue
      ;;
    -T | --upload-file) ghpost::file_operand "${1-}" && shift && data=1 && continue ;;
    --upload-file=*) ghpost::file_operand "${a#*=}" && data=1 && continue ;;
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
    ghpost::at_operand "$v"
  done
  if ((github && data && !get)) && { ((!graphql)) || ghpost::is_mutation "$mark" ${vals[@]+"${vals[@]}"}; }; then
    return 0
  fi
  GHPOST_FILES=("${GHPOST_FILES[@]:0:mark}")
  GHPOST_STDIN=$stdin0
  return 1
}

# ghpost::_wrapper <argv>: 0 when <argv> runs a shell script (`bash x.sh ...`,
# `./x.sh ...`) with a `--` word, which GHPOST_WRAP_AT then counts past.
ghpost::_wrapper() {
  local -a w=("$@")
  local i=0 b="${1##*/}"
  b="${b##*\\}"
  b="${b,,}"
  b="${b%.exe}"
  case "$b" in
  bash | sh | zsh | dash | ksh | mksh)
    i=1
    while [[ "${w[i]-}" == -* ]]; do ((i++)); done
    [[ "${w[i]-}" == *.sh ]] || return 1
    ;;
  *.sh) ;;
  *) return 1 ;;
  esac
  for ((i++; i < ${#w[@]}; i++)); do
    if [[ "${w[i]}" == -- ]]; then
      GHPOST_WRAP_AT=$((i + 1))
      return 0
    fi
  done
  return 1
}

# hook::bash_parse_segments callback: one segment's argv words.
# shellcheck disable=SC2329  # invoked through hook::bash_parse_segments
ghpost::segment() {
  local j cmd form=""
  # What stdin and here-strings feed this segment: read only when it posts,
  # which is judged after the whole parse, so record them now.
  for ((j = 0; j < ${#HOOK_SEG_REDIR_OP[@]}; j++)); do
    ((${HOOK_SEG_REDIR_OPAQUE[j]:-0})) && continue
    case "${HOOK_SEG_REDIR_OP[j]}" in
    '<') GHPOST_AUX_FILES+=("${HOOK_SEG_REDIR_TARGET[j]}") ;;
    '>' | '>>' | '>|' | '<>')
      # Only the sinks; /dev/shm and /dev/../ are ordinary files.
      [[ "${HOOK_SEG_REDIR_TARGET[j]}" =~ ^/dev/(null|stdout|stderr|tty|fd/[0-9]+)$ ]] ||
        GHPOST_WTARGETS+=("${HOOK_SEG_REDIR_TARGET[j]}")
      ;;
    '<<<') GHPOST_AUX_TEXTS+=("${HOOK_SEG_REDIR_TARGET[j]}") ;;
    *) ;;
    esac
  done
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" ghpost::segment
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
  # A script wrapper runs the argv after its `--`, each bare `+++` starting
  # another command: read each one as a segment of its own, with no
  # redirections (those belong to the wrapper).
  if ghpost::_wrapper "$@"; then
    shift "$GHPOST_WRAP_AT"
    local -a inner=() HOOK_SEG_REDIR_OP=() HOOK_SEG_REDIR_FD=() HOOK_SEG_REDIR_TARGET=()
    local -a HOOK_SEG_REDIR_QUOTED=() HOOK_SEG_REDIR_OPAQUE=()
    for j in "$@" +++; do
      if [[ "$j" != +++ ]]; then
        inner+=("$j")
        continue
      fi
      ((${#inner[@]})) && ghpost::segment "${inner[@]}"
      inner=()
    done
    return 0
  fi
  cmd="${1##*/}"
  cmd="${cmd##*\\}"
  cmd="${cmd,,}"
  cmd="${cmd%.exe}"
  shift
  case "$cmd" in
  eval)
    hook::bash_parse_segments "$*" ghpost::segment
    return 0
    ;;
  # A file copied, moved or linked into place may be the body a later post
  # names; its sources are read like `cat` operands.
  cp | mv | ln | install | rsync | tee)
    GHPOST_WTARGETS+=("$cmd")
    for j in "$@"; do
      [[ "$j" == -* ]] || GHPOST_AUX_FILES+=("$j")
    done
    return 0
    ;;
  cat | type | get-content | gc)
    for j in "$@"; do
      [[ "$j" == -* ]] || GHPOST_AUX_FILES+=("$j")
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
        ghpost::gh_body "${@:2}"
        ;;
      *) ;;
      esac
      ;;
    api) ghpost::gh_api "${@:2}" && form="gh-api" ;;
    *) ;;
    esac
    ;;
  curl) ghpost::curl "$@" && form="curl" ;;
  *) ;;
  esac
  [[ -n "$form" ]] || return 0
  [[ -n "$GHPOST_POST" ]] || GHPOST_POST="$form"
  local w rest
  GHPOST_TEXTS+=("$@")
  # A variable or substitution brings its text from elsewhere in the command
  # (`B=...; gh ... --body "$B"`); an unquoted `$(` splits the segment and
  # leaves a word ending in `$`.
  for w in "$@"; do
    [[ "$w" == *'$'* ]] && GHPOST_SUBST=1
  done
  # A quoted `$(cat file)` or `$(<file)` stays inside its word, unparsed.
  # shellcheck disable=SC2016  # a regex: `$(` is matched, not expanded
  local re_sub='(\$\(|`)(cat[[:space:]]+|<[[:space:]]*)([^)`]*)'
  for w in "$@"; do
    rest="$w"
    while [[ "$rest" =~ $re_sub ]]; do
      rest="${rest#*"${BASH_REMATCH[0]}"}"
      for j in ${BASH_REMATCH[3]}; do
        [[ "$j" == -* ]] || GHPOST_FILES+=("${j//[\"\']/}")
      done
    done
  done
  return 0
}

# ghpost::collect <command> <cwd> <tool name>
ghpost::collect() {
  ghpost::reset
  GHPOST_COMMAND="$1"
  GHPOST_CWD="${2:-$PWD}"
  GHPOST_TOOL="${3:-Bash}"
  hook::bash_parse_segments "$1" ghpost::segment
}

# ghpost::_add <kind> <src> <text>
ghpost::_add() {
  GHPOST_BODY_KIND+=("$1")
  GHPOST_BODY_SRC+=("$2")
  GHPOST_BODY+=("$3")
}

# ghpost::bodies: what the collected post carries, in judging order.
#
# The body may sit anywhere in the command when a posting command reads stdin
# or expands a variable or substitution, when it posts a body file and the
# command writes a file (a redirect other than to a /dev sink, or cp, mv, ln,
# install, rsync, tee: `printf ... > x && mv x b.md && gh pr comment 1 -F b.md`),
# when a body file does not exist yet, or on PowerShell (whose quoting the bash
# tokenizer only approximates): then all of it is read. A backtick may open a
# substitution too, but ``` in a fenced body is one as well, so it adds only
# the files `cat` and `<` name. Otherwise only the posting command's words and
# files are read, so a grep beside an unrelated post stays out.
ghpost::bodies() {
  local f c
  GHPOST_BODY=()
  GHPOST_BODY_SRC=()
  GHPOST_BODY_KIND=()
  GHPOST_PATHS=(${GHPOST_FILES[@]+"${GHPOST_FILES[@]}"} ${GHPOST_AUX_FILES[@]+"${GHPOST_AUX_FILES[@]}"})
  for f in ${GHPOST_FILES[@]+"${GHPOST_FILES[@]}"}; do
    # A body file may hold what the command itself writes (a redirect, or a
    # cp, mv or ln into its name), not what is on disk now.
    ((${#GHPOST_WTARGETS[@]})) && GHPOST_WRITES=1
    if ghpost::read_to c "$f"; then
      ghpost::_add file "$f" "$c"
    else
      GHPOST_WRITES=1
    fi
  done
  local -a files=()
  GHPOST_WHOLE=0
  if ((GHPOST_STDIN || GHPOST_SUBST || GHPOST_WRITES)) || [[ "$GHPOST_TOOL" == PowerShell ]]; then
    GHPOST_WHOLE=1
    ghpost::_add command "" "$GHPOST_COMMAND"
    for c in ${GHPOST_TEXTS[@]+"${GHPOST_TEXTS[@]}"}; do ghpost::_add word "" "$c"; done
    for c in ${GHPOST_AUX_TEXTS[@]+"${GHPOST_AUX_TEXTS[@]}"}; do ghpost::_add aux "" "$c"; done
    files=(${GHPOST_AUX_FILES[@]+"${GHPOST_AUX_FILES[@]}"})
  else
    for c in ${GHPOST_TEXTS[@]+"${GHPOST_TEXTS[@]}"}; do ghpost::_add word "" "$c"; done
    [[ "$GHPOST_COMMAND" == *'`'* ]] && files=(${GHPOST_AUX_FILES[@]+"${GHPOST_AUX_FILES[@]}"})
  fi
  for f in ${files[@]+"${files[@]}"}; do
    ghpost::read_to c "$f" && ghpost::_add aux "$f" "$c"
  done
  return 0
}

# ghpost::heredocs: GHPOST_HEREDOCS, each here-doc body of the collected
# command, sliced from the byte offsets the parse left in HOOK_HEREDOC_BODIES.
# For a caller that judges the bodies a whole-command read would cover
# without the rest of the command: empty unless ghpost::bodies found that the
# whole command counts (GHPOST_WHOLE), so a here-doc that feeds no post stays
# out.
ghpost::heredocs() {
  GHPOST_HEREDOCS=()
  ((${GHPOST_WHOLE:-0})) || return 0
  hook::_c_locale ghpost::_heredocs_c
}
# shellcheck disable=SC2329  # invoked through hook::_c_locale
ghpost::_heredocs_c() {
  local e s t
  for e in ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}; do
    s="${e%% *}"
    e="${e#* }"
    t="${e%% *}"
    GHPOST_HEREDOCS+=("${GHPOST_COMMAND:s:t-s}")
  done
}
