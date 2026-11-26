#!/usr/bin/env bash
set -uo pipefail

export LC_ALL=C

[[ "${CLAUDE_PLUGIN_OPTION_PR_BODY_LINKAGE_GATE_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PreToolUse" "source-control" "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.cwd' || exit 0
COMMAND="${HOOK_JQ_FIELDS[0]}"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
while [[ "$HOOK_CWD" == *$'\n' ]]; do HOOK_CWD="${HOOK_CWD%$'\n'}"; done
[[ -n "$COMMAND" ]] || exit 0
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Hh][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *"pr"* ]] || exit 0

REPO_ROOT=""
hook::repo_root_to REPO_ROOT "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" || :

# shellcheck source=pr-linkage-scope.sh
source "$HOOK_DIR/pr-linkage-scope.sh"
GATE_FILE=""
linkage::gate_file_to GATE_FILE "$REPO_ROOT" "pr-body-linkage-gate"
[[ -n "$GATE_FILE" ]] || exit 0

FORM=""
DIR_CHANGED=0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data outcome "$1" form "$FORM"
  hook::emit_telemetry "pr-body-linkage-gate" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# shellcheck source=pr-linkage-validator.sh
source "$HOOK_DIR/pr-linkage-validator.sh"

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sole_heredoc_body_to() {
  local __pbl_dest="$1" text="$2" line delim="" in_hd=0 t out="" count=0 li=0
  local start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'
  printf -v "$__pbl_dest" '%s' ""
  linkage::split_lines "$text"
  for ((li = 0; li < ${#LINKAGE_LINES[@]}; li++)); do
    line="${LINKAGE_LINES[li]}"
    if ((in_hd)); then
      t="${line%$'\r'}"
      t="${t#"${t%%[![:space:]]*}"}"
      t="${t%"${t##*[![:space:]]}"}"
      [[ "$t" == "$delim" ]] && {
        in_hd=0
        continue
      }
      out+="${line%$'\r'}"$'\n'
      continue
    fi
    if [[ "$line" =~ $start_re ]]; then
      ((count++))
      ((count > 1)) && return 1
      delim="${BASH_REMATCH[2]}"
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      in_hd=1
    fi
  done
  ((count == 1 && in_hd == 0)) || return 1
  linkage::chomp_to "$__pbl_dest" "$out"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_dynamic() {
  [[ "$1" == *'$'* || "$1" == *'`'* ]]
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
validate_body() {
  # shellcheck disable=SC2310  # the return status IS the verdict
  linkage::blocking_problems "$1" && return 0
  linkage::block_message "${GATE_FILE#"$REPO_ROOT/"}"
  emit_tel "blocked"
  exit 2
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
takes_value() {
  case "$1" in
  --assignee | --base | --body | --body-file | --head | --label | --milestone | \
    --project | --reviewer | --template | --title | --repo | --recover | \
    --add-assignee | --add-label | --add-project | --add-reviewer | \
    --remove-assignee | --remove-label | --remove-project | --remove-reviewer)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# Sets SHORT_KIND (body|file|repo|other|unknown), SHORT_VAL, SHORT_ATE_NEXT.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
parse_short_cluster() {
  local word="$1" next="$2" have_next="$3"
  local rest="${word#-}" c
  SHORT_KIND="other"
  SHORT_VAL=""
  SHORT_ATE_NEXT=0
  while [[ -n "$rest" ]]; do
    c="${rest:0:1}"
    rest="${rest:1}"
    case "$c" in
    b | F | R | a | B | H | l | m | p | r | T | t)
      if [[ -n "$rest" ]]; then
        SHORT_VAL="$rest"
      elif ((have_next)); then
        SHORT_VAL="$next"
        SHORT_ATE_NEXT=1
      else
        SHORT_KIND="unknown"
        return 0
      fi
      case "$c" in
      b) SHORT_KIND="body" ;;
      F) SHORT_KIND="file" ;;
      R) SHORT_KIND="repo" ;;
      *) SHORT_KIND="other" ;;
      esac
      return 0
      ;;
    d | e | f | w) ;;
    *)
      SHORT_KIND="unknown"
      return 0
      ;;
    esac
  done
  return 0
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
parse_wrapper_flag() {
  local wrapper="$1" word="$2" next="$3" have_next="$4"
  local rest c
  WRAP_KIND="none"
  WRAP_VAL=""
  WRAP_ATE_NEXT=0

  case "$word" in
  --*)
    case "$wrapper:${word%%=*}" in
    env:--chdir | sudo:--chdir | sudo:--chroot | sudo:--login)
      WRAP_KIND="chdir"
      return 0
      ;;
    env:--split-string) WRAP_KIND="split" ;;
    env:--unset | sudo:--user | sudo:--group | sudo:--host | sudo:--prompt | \
      sudo:--close-from | sudo:--command-timeout | sudo:--other-user | \
      sudo:--role | sudo:--type)
      WRAP_KIND="value"
      ;;
    env:--help | env:--version | sudo:--help | sudo:--version)
      WRAP_KIND="terminal"
      return 0
      ;;
    env:--ignore-environment | env:--null | env:--debug | env:--list-signal-handling | \
      env:--block-signal | env:--default-signal | env:--ignore-signal | \
      sudo:--askpass | sudo:--background | sudo:--bell | sudo:--preserve-env | \
      sudo:--set-home | sudo:--remove-timestamp | sudo:--reset-timestamp | \
      sudo:--non-interactive | sudo:--preserve-groups | sudo:--stdin | \
      sudo:--shell | sudo:--validate)
      return 0
      ;;
    *)
      WRAP_KIND="unknown"
      return 0
      ;;
    esac
    case "$word" in
    *=*) WRAP_VAL="${word#*=}" ;;
    *)
      if ((have_next)); then
        WRAP_VAL="$next"
        WRAP_ATE_NEXT=1
      else
        WRAP_KIND="none"
      fi
      ;;
    esac
    return 0
    ;;
  *) ;;
  esac

  rest="${word#-}"
  while [[ -n "$rest" ]]; do
    c="${rest:0:1}"
    rest="${rest:1}"
    case "$wrapper:$c" in
    env:C | sudo:D | sudo:R | sudo:i)
      WRAP_KIND="chdir"
      return 0
      ;;
    env:S) WRAP_KIND="split" ;;
    env:u | sudo:u | sudo:g | sudo:h | sudo:p | sudo:C | sudo:T | sudo:U | sudo:r | sudo:t)
      WRAP_KIND="value"
      ;;
    sudo:V)
      WRAP_KIND="terminal"
      return 0
      ;;
    command:p | \
      env:i | env:0 | env:v | sudo:A | sudo:B | sudo:b | sudo:E | sudo:H | sudo:K | \
      sudo:k | sudo:n | sudo:P | sudo:S | sudo:s | sudo:v)
      continue
      ;;
    *)
      WRAP_KIND="unknown"
      return 0
      ;;
    esac
    if [[ -n "$rest" ]]; then
      WRAP_VAL="$rest"
    elif ((have_next)); then
      WRAP_VAL="$next"
      WRAP_ATE_NEXT=1
    else
      WRAP_KIND="none"
    fi
    return 0
  done
  return 0
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local n=$# i=0 d k word next have_next bin wrapper split_from reparse qword
  local body_flag="" body_val="" body=""

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done

  d=$i
  while ((d < n)); do
    case "${w[d]}" in
    command | builtin | eval | -p) ((d++)) ;;
    *) break ;;
    esac
  done
  case "${w[d]:-}" in
  cd | pushd | popd)
    DIR_CHANGED=1
    return 0
    ;;
  *) ;;
  esac
  ((DIR_CHANGED)) && return 0

  while ((i < n)); do
    word="${w[i]}"
    if [[ "$word" == *=* && "$word" != -* ]]; then
      ((i++))
      continue
    fi
    case "${word##*/}" in
    env | command | sudo)
      wrapper="${word##*/}"
      ((i++))
      while ((i < n)); do
        case "${w[i]}" in
        --)
          ((i++))
          break
          ;;
        -*)
          parse_wrapper_flag "$wrapper" "${w[i]}" "${w[i + 1]:-}" "$((i + 1 < n))"
          case "$WRAP_KIND" in
          chdir | terminal) return 0 ;;
          split)
            split_from=$((i + 1))
            ((WRAP_ATE_NEXT)) && split_from=$((i + 2))
            reparse="$WRAP_VAL"
            for ((k = split_from; k < n; k++)); do
              printf -v qword '%q' "${w[k]}"
              reparse+=" $qword"
            done
            hook::bash_parse_segments "$reparse" check_segment
            return 0
            ;;
          value) ((WRAP_ATE_NEXT)) && ((i++)) ;;
          unknown) return 0 ;;
          *) ;;
          esac
          ((i++))
          ;;
        *=*) ((i++)) ;;
        *) break ;;
        esac
      done
      continue
      ;;
    *) break ;;
    esac
  done

  bin="${w[i]:-}"
  bin="${bin//\\//}"
  bin="${bin##*/}"
  bin="${bin,,}"
  bin="${bin%.exe}"
  [[ "$bin" == "gh" && "${w[i + 1]:-}" == "pr" ]] || return 0
  case "${w[i + 2]:-}" in
  create | new | edit) ;;
  *) return 0 ;;
  esac

  for ((i = i + 3; i < n; i++)); do
    word="${w[i]}"
    next=""
    have_next=0
    ((i + 1 < n)) && {
      next="${w[i + 1]}"
      have_next=1
    }
    case "$word" in
    --) break ;;
    --repo | --repo=*) return 0 ;;
    --body)
      ((have_next)) || return 0
      body_flag="body"
      body_val="$next"
      ((i++))
      ;;
    --body=*)
      body_flag="body"
      body_val="${word#--body=}"
      ;;
    --body-file)
      ((have_next)) || return 0
      body_flag="file"
      body_val="$next"
      ((i++))
      ;;
    --body-file=*)
      body_flag="file"
      body_val="${word#--body-file=}"
      ;;
    --*)
      # shellcheck disable=SC2310  # takes_value is a pure classifier; a false return is the "no value" case
      if takes_value "$word"; then ((i++)); fi
      ;;
    -?*)
      parse_short_cluster "$word" "$next" "$have_next"
      case "$SHORT_KIND" in
      repo) return 0 ;;
      body | file)
        body_flag="$SHORT_KIND"
        body_val="$SHORT_VAL"
        ;;
      *) ;;
      esac
      ((SHORT_ATE_NEXT)) && ((i++))
      ;;
    *) ;;
    esac
  done

  [[ -n "$body_flag" ]] || return 0

  if [[ "$body_flag" == "file" ]]; then
    if [[ "$body_val" == "-" ]]; then
      sole_heredoc_body_to body "$COMMAND" || return 0
      FORM="stdin-heredoc"
    else
      local path="$body_val"
      [[ "$path" == /* || "$path" =~ ^[A-Za-z]:[\\/] ]] || path="${HOOK_CWD:-$REPO_ROOT}/$path"
      [[ -r "$path" && -f "$path" ]] || return 0
      body=$(<"$path") || return 0
      FORM="body-file"
    fi
  else
    # shellcheck disable=SC2310  # is_dynamic is a pure predicate; both branches are handled
    if is_dynamic "$body_val"; then
      sole_heredoc_body_to body "$body_val" || return 0
      FORM="body-substitution"
    else
      body="$body_val"
      FORM="body-literal"
    fi
  fi

  validate_body "$body"
  return 0
}

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok"
exit 0
