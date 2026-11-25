#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_WINDOWS_DRIVE_TMP_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-windows-drive-tmp PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*) exit 0 ;;
esac

# shellcheck disable=SC2089,SC2090  # quotes in the character class are literal
_DRIVE_TMP_CREATOR_QUOTED="((^|[[:space:]])sudo[[:space:]]+|^[[:space:]]*)[\"']([^[:space:]\"']*/)?(tee|mktemp|mkdir|touch|dd|tee\.exe)[\"']([[:space:]]|\$)"
_DRIVE_TMP_CREATOR_UNQUOTED="((^|[[:space:]])sudo[[:space:]]+|^[[:space:]]*)([^[:space:]\"']*/)?(tee|mktemp|mkdir|touch|dd|tee\.exe)([[:space:]]|\$)"
_DRIVE_TMP_CREATOR_BARE="[[:space:]](tee|mktemp|mkdir|touch|dd|tee\.exe)([[:space:]]|\$)"
_DRIVE_TMP_COPY_QUOTED="((^|[[:space:]])sudo[[:space:]]+|^[[:space:]]*)[\"']([^[:space:]\"']*/)?(cp|mv|install|install\.exe|copy-item|move-item|copy|move|cpi|mi)[\"']([[:space:]]|\$)"
_DRIVE_TMP_COPY_UNQUOTED="((^|[[:space:]])sudo[[:space:]]+|^[[:space:]]*)([^[:space:]\"']*/)?(cp|mv|install|install\.exe|copy-item|move-item|copy|move|cpi|mi)([[:space:]]|\$)"
_DRIVE_TMP_COPY_BARE="[[:space:]](cp|mv|install|install\.exe|copy-item|move-item|copy|move|cpi|mi)([[:space:]]|\$)"

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq_blocking "guardrails-block-windows-drive-tmp" "block_windows_drive_tmp_enabled"

jq_rc=0
hook::jq_fields "$INPUT" \
  '.tool_input.command' '.tool_name' \
  '.tool_input.file_path' '.tool_input.notebook_path' || jq_rc=$?
guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))

COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"

FILE_PATH="${HOOK_JQ_FIELDS[2]:-}"
[[ -n "$FILE_PATH" ]] || FILE_PATH="${HOOK_JQ_FIELDS[3]:-}"

[[ -n "$COMMAND" || -n "$FILE_PATH" ]] || exit 0

MAX_COMMAND_LEN=16384

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local SUBJECT data
  hook::extract_bash_subject_to SUBJECT "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$SUBJECT" form "$2"
  hook::emit_telemetry "block-windows-drive-tmp" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  local form="$1"
  # shellcheck disable=SC2016
  printf '%s\n' \
    'BLOCKED: write target is a drive-root temp path (<drive>:\tmp), not the platform temp directory.' \
    'Fix: write under %TEMP% / $TEMP / $env:TEMP (or $TMP / $TMPDIR when they point there); /var/tmp also works.' >&2
  emit_tel "blocked" "$form"
  exit 2
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long"
fi

norm_lower() {
  local s="${1//\\//}"
  NORM_OUT="${s,,}"
}

norm_lower "$COMMAND"
NORM="$NORM_OUT"

backslash_tmp_to_msys_root_to() {
  local __dt_dest="$1" __dt_rest="$2" __dt_out="" __dt_l __dt_r
  while [[ "$__dt_rest" == *'\tmp'* ]]; do
    __dt_out+="${__dt_rest%%\\tmp*}"
    __dt_rest="${__dt_rest#*\\tmp}"
    __dt_l="${__dt_out: -1}"
    __dt_r="${__dt_rest:0:1}"
    if [[ "$__dt_l" == [[:alnum:]._/:] || "$__dt_l" == "\\" || "$__dt_r" == [[:alnum:]_.-] ]]; then
      __dt_out+='\tmp'
    else
      __dt_out+='/c/tmp'
    fi
  done
  printf -v "$__dt_dest" '%s' "$__dt_out$__dt_rest"
}

_DRIVE_TMP_POSIX_USERTEMP=""
_DRIVE_TMP_SKIP_POSIX=0

posix_tmp_maps_to_usertemp() {
  if [[ -n "$_DRIVE_TMP_POSIX_USERTEMP" ]]; then
    return "$_DRIVE_TMP_POSIX_USERTEMP"
  fi
  _DRIVE_TMP_POSIX_USERTEMP=1
  local tmp_win="" temp_win="" temp_env mount_out mount_line tmp_n temp_n
  temp_env="${TEMP:-${TMP:-}}"
  if command -v cygpath >/dev/null 2>&1 && [[ -n "$temp_env" ]]; then
    tmp_win=$(cygpath -w /tmp 2>/dev/null) || tmp_win=""
    if [[ -n "$tmp_win" ]]; then
      temp_win=$(cygpath -w "$temp_env" 2>/dev/null) || temp_win="$temp_env"
      norm_lower "$tmp_win"
      tmp_n="${NORM_OUT%/}"
      norm_lower "$temp_win"
      temp_n="${NORM_OUT%/}"
      if [[ -n "$tmp_n" && -n "$temp_n" && ( "$tmp_n" == "$temp_n" || "$tmp_n" == "$temp_n"/* ) ]]; then
        _DRIVE_TMP_POSIX_USERTEMP=0
        return 0
      fi
    fi
  fi
  mount_out=$(mount 2>/dev/null) || mount_out=""
  while IFS= read -r mount_line; do
    if [[ "$mount_line" == *" on /tmp "* && "$mount_line" == *"usertemp"* ]]; then
      _DRIVE_TMP_POSIX_USERTEMP=0
      return 0
    fi
  done <<<"$mount_out"
  return 1
}

has_drive_root_tmp() {
  local s="$1"
  if ((_DRIVE_TMP_SKIP_POSIX == 0)) &&
    [[ "$s" =~ (^|[^[:alnum:]._/])\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
    return 0
  fi
  if [[ "$s" =~ (^|[^[:alnum:]._/:])\/[a-z]\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
    return 0
  fi
  if [[ "$s" =~ ([^[:alnum:]]|[[:alnum:]][[:alnum:]]|-[[:alnum:]]):\/[a-z]\/tmp(\/|[^[:alnum:]_./-]|$) ]]; then
    return 0
  fi
  [[ "$s" =~ (^|[^[:alnum:]])[a-z]:\/tmp(\/|[^[:alnum:]_./-]|$) ]]
}

mask_quoted_redirect_ops_to() {
  local __dt_dest="$1" __dt_s="$2" __dt_out="" __dt_i=0 __dt_c __dt_quote=""
  local -i __dt_len=${#__dt_s}
  while ((__dt_i < __dt_len)); do
    __dt_c="${__dt_s:__dt_i:1}"
    if [[ -n "$__dt_quote" ]]; then
      if [[ "$__dt_c" == "$__dt_quote" ]]; then
        __dt_quote=""
        __dt_out+="$__dt_c"
      elif [[ "$__dt_c" == '>' ]]; then
        __dt_out+='#'
      else
        __dt_out+="$__dt_c"
      fi
    else
      if [[ "$__dt_c" == "'" || "$__dt_c" == '"' ]]; then
        __dt_quote="$__dt_c"
      fi
      __dt_out+="$__dt_c"
    fi
    __dt_i=$((__dt_i + 1))
  done
  printf -v "$__dt_dest" '%s' "$__dt_out"
}

has_redirect_to_drive_root_tmp() {
  local s
  mask_quoted_redirect_ops_to s "$1"
  # the portability gate does not flag this ERE. portability-ok: bash [[ =~ ]]
  if [[ "$s" =~ (^|[^>&])\&?[0-9]*\>\>?[[:space:]]*[\"\']?(\/[a-z]\/tmp|[a-z]:\/tmp)(\/|[\"\'[:space:]\;|&<>()]|$) ]]; then
    return 0
  fi
  ((_DRIVE_TMP_SKIP_POSIX == 0)) &&
    # portability-ok: character-class angle brackets in a bash regex, not a GNU word boundary
    [[ "$s" =~ (^|[^>&])\&?[0-9]*\>\>?[[:space:]]*[\"\']?\/tmp(\/|[\"\'[:space:]\;|&<>()]|$) ]]
}

split_shell_segments() {
  local s="$1" out="" i=0 c quote="" nex
  local -i len=${#s}
  while ((i < len)); do
    c="${s:i:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$c" == "$quote" ]]; then
        quote=""
      fi
      out+="$c"
      i=$((i + 1))
      continue
    fi
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      quote="$c"
      out+="$c"
      i=$((i + 1))
      continue
    fi
    if [[ "$c" == ';' || "$c" == '|' || "$c" == '&' ]]; then
      printf '%s\0' "$out"
      out=""
      nex="${s:i+1:1}"
      if [[ ( "$c" == '&' || "$c" == '|' ) && "$nex" == "$c" ]]; then
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
      continue
    fi
    out+="$c"
    i=$((i + 1))
  done
  printf '%s\0' "$out"
}

segment_destination_operand_to() {
  local __dt_dest="$1" __dt_tok __dt_out="" __dt_expect=0
  local -a __dt_tokens=()
  # Intentional word-split of the static matcher subject into tokens.
  # shellcheck disable=SC2206
  __dt_tokens=( $2 )
  for __dt_tok in "${__dt_tokens[@]}"; do
    __dt_tok="${__dt_tok#\'}"
    __dt_tok="${__dt_tok%\'}"
    __dt_tok="${__dt_tok#\"}"
    __dt_tok="${__dt_tok%\"}"
    if ((__dt_expect)); then
      __dt_out="$__dt_tok"
      __dt_expect=0
      continue
    fi
    case "$__dt_tok" in
    -t | --target-directory | --target-directory=* | -destination | -destination:* | -dest | -dest:*)
      if [[ "$__dt_tok" == *=* || "$__dt_tok" == *:* ]]; then
        __dt_out="${__dt_tok#*=}"
        __dt_out="${__dt_out#*:}"
      else
        __dt_expect=1
      fi
      ;;
    -*)
      continue
      ;;
    tee | mktemp | mkdir | touch | install | cp | mv | dd | install.exe | tee.exe | \
    set-content | add-content | out-file | tee-object | new-item | export-clixml | \
    export-csv | copy-item | move-item | copy | move | cpi | mi | ac | ni)
      ;;
    *)
      __dt_out="$__dt_tok"
      ;;
    esac
  done
  printf -v "$__dt_dest" '%s' "$__dt_out"
}

segment_downloader_output_operand_to() {
  local __dt_dest="$1" __dt_tok __dt_out="" __dt_expect=0 __dt_pre __dt_rest
  local -a __dt_tokens=()
  # Intentional word-split of the static matcher subject into tokens.
  # shellcheck disable=SC2206
  __dt_tokens=( $2 )
  for __dt_tok in "${__dt_tokens[@]}"; do
    __dt_tok="${__dt_tok#\'}"
    __dt_tok="${__dt_tok%\'}"
    __dt_tok="${__dt_tok#\"}"
    __dt_tok="${__dt_tok%\"}"
    if ((__dt_expect)); then
      __dt_out+=" $__dt_tok"
      __dt_expect=0
      [[ "$__dt_tok" == -* ]] || continue
    fi
    case "$__dt_tok" in
    --output=* | --output-document=* | --output-dir=*)
      __dt_out+=" ${__dt_tok#*=}"
      ;;
    --output | --output-document | --output-dir)
      __dt_expect=1
      ;;
    *)
      __dt_pre="${__dt_tok%%[oO]*}"
      if [[ "$__dt_pre" != "$__dt_tok" && "$__dt_pre" =~ ^-[[:alpha:]]*$ ]]; then
        __dt_rest="${__dt_tok#"$__dt_pre"?}"
        if [[ -n "$__dt_rest" ]]; then
          __dt_out+=" $__dt_rest"
        else
          __dt_expect=1
        fi
      fi
      ;;
    esac
  done
  printf -v "$__dt_dest" '%s' "$__dt_out"
}

segment_leading_exe_verb_to() {
  local __dt_dest="$1" __dt_s="$2" __dt_word __dt_verb
  __dt_s="${__dt_s#"${__dt_s%%[![:space:]]*}"}"
  if [[ "$__dt_s" =~ ^sudo[[:space:]]+(.*) ]]; then
    __dt_s="${BASH_REMATCH[1]}"
    __dt_s="${__dt_s#"${__dt_s%%[![:space:]]*}"}"
  fi
  if [[ "$__dt_s" == \"* ]]; then
    __dt_word="${__dt_s#\"}"
    __dt_word="${__dt_word%%\"*}"
  elif [[ "$__dt_s" == \'* ]]; then
    __dt_word="${__dt_s#\'}"
    __dt_word="${__dt_word%%\'*}"
  else
    __dt_word="${__dt_s%%[[:space:]]*}"
  fi
  [[ "$__dt_word" == */* || "$__dt_word" == *.exe ]] || return 1
  __dt_verb="${__dt_word##*/}"
  __dt_verb="${__dt_verb,,}"
  __dt_verb="${__dt_verb%.exe}"
  case "$__dt_verb" in
  tee | mktemp | mkdir | touch | dd | cp | mv | install) ;;
  *) return 1 ;;
  esac
  printf -v "$__dt_dest" '%s' "$__dt_verb"
}

segment_writes_drive_root_tmp() {
  local subject="$1" dest lead=""
  if segment_leading_exe_verb_to lead "$subject"; then
    case "$lead" in
    tee | mktemp | mkdir | touch | dd)
      has_drive_root_tmp "$subject"
      return
      ;;
    cp | mv | install)
      segment_destination_operand_to dest "$subject"
      [[ -n "$dest" ]] && has_drive_root_tmp "$dest"
      return
      ;;
    *) ;;
    esac
  fi
  if [[ "$subject" =~ $_DRIVE_TMP_CREATOR_QUOTED ]] ||
    [[ "$subject" =~ $_DRIVE_TMP_CREATOR_UNQUOTED ]] ||
    [[ "$subject" =~ $_DRIVE_TMP_CREATOR_BARE ]] ||
    [[ "$subject" =~ (^|[[:space:];|&]|/)(set-content|add-content|out-file|tee-object|new-item|export-clixml|export-csv)([[:space:]]|:|$) ]] ||
    [[ "$subject" =~ (^|[[:space:]])(ac|ni)([[:space:]]|$) ]]; then
    has_drive_root_tmp "$subject"
    return
  fi
  if [[ "$subject" =~ $_DRIVE_TMP_COPY_QUOTED ]] ||
    [[ "$subject" =~ $_DRIVE_TMP_COPY_UNQUOTED ]] ||
    [[ "$subject" =~ $_DRIVE_TMP_COPY_BARE ]]; then
    segment_destination_operand_to dest "$subject"
    [[ -n "$dest" ]] && has_drive_root_tmp "$dest"
    return
  fi
  if [[ "$subject" =~ (^|[[:space:];|&]|/)(curl|wget|curl\.exe|wget\.exe)([[:space:]]|$) ]]; then
    segment_downloader_output_operand_to dest "$subject"
    [[ -n "$dest" ]] && has_drive_root_tmp "$dest"
    return
  fi
  if [[ "$subject" =~ (write_text|write_bytes|makedirs)[[:space:]]*\( ]]; then
    has_drive_root_tmp "$subject" && inline_code_can_run
    return
  fi
  local py_open="open[[:space:]]*\\(|['\"]open['\"]\\)[[:space:]]*\\("
  if [[ "$subject" =~ $py_open ]]; then
    has_drive_root_tmp "$subject" && inline_code_can_run || return 1
    if [[ -z "$_DRIVE_TMP_OPEN_RC" ]]; then
      _DRIVE_TMP_OPEN_RC=0
      command_is_one_python_run "$NORM" && command_opens_only_for_read "$NORM" && _DRIVE_TMP_OPEN_RC=1
    fi
    return "$_DRIVE_TMP_OPEN_RC"
  fi
  return 1
}

collapse_quoted_to() {
  local __dt_dest="$1" __dt_rest="$2" __dt_bare="" __dt_q
  while [[ "$__dt_rest" =~ ^([^\"\']*)([\"\']) ]]; do
    __dt_bare+="${BASH_REMATCH[1]}Q"
    __dt_q="${BASH_REMATCH[2]}"
    __dt_rest="${__dt_rest:${#BASH_REMATCH[0]}}"
    [[ "$__dt_rest" == *"$__dt_q"* ]] || return 1
    __dt_rest="${__dt_rest#*"$__dt_q"}"
  done
  printf -v "$__dt_dest" '%s' "$__dt_bare$__dt_rest"
}

_DRIVE_TMP_DATA_ONLY="^[[:space:]]*(gh[[:blank:]]+(issue|pr)[[:blank:]]+(create|comment|edit)|git[[:blank:]]+(commit|tag)|echo|printf)([[:blank:]]+[A-Za-z0-9_.,:=@%+/-]+)*[[:blank:]]*$"
_DRIVE_TMP_CODE_RC=""
inline_code_can_run() {
  if [[ -z "$_DRIVE_TMP_CODE_RC" ]]; then
    _DRIVE_TMP_CODE_RC=0
    if [[ "$TOOL_NAME" == Bash && "$COMMAND" != *[\\\$\`]* ]] &&
      [[ "$COMMAND" != *'<('* && "$COMMAND" != *'>('* ]]; then
      local bare
      collapse_quoted_to bare "$COMMAND" && [[ "$bare" =~ $_DRIVE_TMP_DATA_ONLY ]] && _DRIVE_TMP_CODE_RC=1
    fi
  fi
  return "$_DRIVE_TMP_CODE_RC"
}

_DRIVE_TMP_PY_LIT="(\"[[:alnum:]_./:~ -]*\"|'[[:alnum:]_./:~ -]*')"
_DRIVE_TMP_PY_READ_MODE="(\"[rbt]+\"|'[rbt]+')"
_DRIVE_TMP_PY_READ_KWARG="[[:space:]]*,[[:space:]]*(encoding|errors|newline)[[:space:]]*=[[:space:]]*${_DRIVE_TMP_PY_LIT}"
_DRIVE_TMP_PY_OPEN_READ="^[[:space:]]*([rbu]*${_DRIVE_TMP_PY_LIT}|[[:alnum:]_.]+(\[[0-9]+\])*)([[:space:]]*,[[:space:]]*(mode[[:space:]]*=[[:space:]]*)?${_DRIVE_TMP_PY_READ_MODE})?(${_DRIVE_TMP_PY_READ_KWARG})*[[:space:]]*\)"
_DRIVE_TMP_PY_READ_CHAIN="^[[:space:]]*\.[[:space:]]*(read|readline|readlines)[[:space:]]*\("
_DRIVE_TMP_PY_JSON_LOAD="(^|[^[:alnum:]_.])json[[:space:]]*\.[[:space:]]*load[[:space:]]*\([[:space:]]*$"
_DRIVE_TMP_PY_IMPORT_JSON="(^|[;\"'"$'\n'"])[[:space:]]*import[[:space:]]+json([[:space:]]*[,;\"'"$'\n'"]|[[:space:]]*$)"
_DRIVE_TMP_PY_INDIRECTION="(^|[^[:alnum:]_])(exec[a-z]*|eval|compile|getattr|setattr|globals|locals|vars|__import__|__builtins__|builtins|importlib|__dict__|system|popen[0-9]*|spawn[a-z]*|subprocess|shutil|rename|renames|replace|mknod|mkfifo|link|symlink|truncate|mkdir|makedirs|touch|write_text|write_bytes|copy[a-z0-9]*|move|io|codecs|tempfile|ctypes|pty|pickle|marshal|shelve|yaml|dill)([^[:alnum:]_]|$)"
_DRIVE_TMP_OPEN_RC=""
command_opens_only_for_read() {
  local rest="$1" before out="" call ws t
  [[ "$COMMAND" == *[\\\$\`]* ]] && return 1
  [[ "$rest" =~ $_DRIVE_TMP_PY_INDIRECTION ]] && return 1
  [[ "$rest" =~ import[[:space:]]*\* ]] && return 1
  t="${rest//json.load(/ }"
  t="${t//json.loads(/ }"
  while [[ "$t" =~ $_DRIVE_TMP_PY_IMPORT_JSON ]]; do
    t="${t/"${BASH_REMATCH[0]}"/ }"
  done
  [[ "$t" =~ (^|[^[:alnum:]_.])json([^[:alnum:]_]|$) ]] && return 1
  while [[ "$rest" == *open* ]]; do
    before="${rest%%open*}"
    rest="${rest#*open}"
    if [[ "${rest:0:1}" == [[:alnum:]_] ]]; then
      out+="${before}open"
      continue
    fi
    ws="${rest%%[![:space:]]*}"
    if [[ "${rest:${#ws}:1}" != '(' ]]; then
      [[ "${before: -1}" == [[:alnum:]_] ]] || return 1
      out+="${before}open"
      continue
    fi
    t="${before%"${before##*[![:space:]]}"}"
    [[ "${before: -1}" == [[:alnum:]_:] || "${t: -1}" == . ]] && return 1
    rest="${rest:${#ws}+1}"
    [[ "$rest" =~ $_DRIVE_TMP_PY_OPEN_READ ]] || return 1
    call="${BASH_REMATCH[0]}"
    rest="${rest:${#call}}"
    if [[ ! "$rest" =~ $_DRIVE_TMP_PY_READ_CHAIN ]]; then
      [[ "$before" =~ $_DRIVE_TMP_PY_JSON_LOAD && "$rest" =~ ^[[:space:]]*\) ]] || return 1
      t="${before%json*}"
      t="${t%"${t##*[![:space:]]}"}"
      [[ "${t: -1}" == . ]] && return 1
    fi
    out+="$before"
  done
  [[ "$out$rest" == *tmp* ]] && return 1
  return 0
}

_DRIVE_TMP_PY_RUN="^[[:space:]]*(python([0-9]+(\.[0-9]+)*)?|py)(\.exe)?([[:blank:]]+(-[beiopqrsu]+|-[0-9]+(\.[0-9]+)*))*"
_DRIVE_TMP_PY_RUN_C="${_DRIVE_TMP_PY_RUN}[[:blank:]]+-c[[:blank:]]+Q[[:blank:]]*\$"
_DRIVE_TMP_PY_RUN_HEREDOC="${_DRIVE_TMP_PY_RUN}([[:blank:]]+-)?[[:blank:]]*<<[[:blank:]]*('[a-z_][a-z0-9_]*'|\"[a-z_][a-z0-9_]*\"|[a-z_][a-z0-9_]*)[[:blank:]]*\$"
command_is_one_python_run() {
  local s="$1" bare first rest line tag ended=0
  if collapse_quoted_to bare "$s" && [[ "$bare" =~ $_DRIVE_TMP_PY_RUN_C ]]; then
    return 0
  fi
  [[ "$s" == *$'\n'* ]] || return 1
  first="${s%%$'\n'*}"
  [[ "$first" =~ $_DRIVE_TMP_PY_RUN_HEREDOC ]] || return 1
  tag="${first##*<<}"
  tag="${tag//[[:blank:]\'\"]/}"
  rest="${s#*$'\n'}"
  while :; do
    line="${rest%%$'\n'*}"
    if ((ended)); then
      [[ -z "${line//[[:space:]]/}" ]] || return 1
    elif [[ "$line" == "$tag" ]]; then
      ended=1
    fi
    [[ "$rest" == *$'\n'* ]] || break
    rest="${rest#*$'\n'}"
  done
  ((ended))
}

has_write_utility_with_drive_root_tmp() {
  local s="$1" piece
  has_drive_root_tmp "$s" || [[ "$s" == *'/tmp'* ]] || return 1
  while IFS= read -r -d '' piece; do
    [[ -n "${piece//[[:space:]]/}" ]] || continue
    if segment_writes_drive_root_tmp "$piece"; then
      return 0
    fi
  done < <(split_shell_segments "$s")
  return 1
}

if [[ -n "$FILE_PATH" ]]; then
  norm_lower "$FILE_PATH"
  if has_drive_root_tmp "$NORM_OUT"; then
    block "file-path"
  fi
fi

if [[ -n "$COMMAND" ]]; then
  _DRIVE_TMP_SKIP_POSIX=0
  _DRIVE_TMP_OPEN_RC=""
  _DRIVE_TMP_CODE_RC=""
  if [[ "$TOOL_NAME" == "Bash" && "$NORM" == *tmp* ]] && posix_tmp_maps_to_usertemp; then
    _DRIVE_TMP_SKIP_POSIX=1
    _dt_lc="${COMMAND,,}"
    if [[ "$_dt_lc" == *'\tmp'* ]]; then
      backslash_tmp_to_msys_root_to _dt_lc "$_dt_lc"
      norm_lower "$_dt_lc"
      NORM="$NORM_OUT"
    fi
  fi
  if has_redirect_to_drive_root_tmp "$NORM"; then
    block "redirect"
  fi

  if has_write_utility_with_drive_root_tmp "$NORM"; then
    block "write-utility"
  fi
fi

emit_tel "ok" ""
exit 0
