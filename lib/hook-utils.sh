# shellcheck shell=bash

[[ -n "${_HOOK_UTILS_LOADED:-}" ]] && return 0
readonly _HOOK_UTILS_LOADED=1

hook::is_enabled() {
  local var_name="CLAUDE_PLUGIN_OPTION_${1}_ENABLED"
  [[ "${!var_name:-true}" == "true" ]]
}

hook::check_enabled() {
  hook::is_enabled "$1" || exit 0
}

hook::json_escape_to() {
  local __hu_s="$2"
  __hu_s="${__hu_s//\\/\\\\}"
  __hu_s="${__hu_s//\"/\\\"}"
  __hu_s="${__hu_s//$'\n'/\\n}"
  __hu_s="${__hu_s//$'\r'/\\r}"
  __hu_s="${__hu_s//$'\t'/\\t}"
  if [[ "$__hu_s" == *[[:cntrl:]]* ]]; then
    __hu_s="${__hu_s//[$'\001'-$'\010'$'\013'$'\014'$'\016'-$'\037']/}"
  fi
  printf -v "$1" '%s' "$__hu_s"
}

hook::json_escape() {
  local __hu_e
  hook::json_escape_to __hu_e "$1"
  printf '%s' "$__hu_e"
}

hook::emit_channels() {
  local event="$1" ctx="$2" sysmsg="$3"
  [[ -n "$ctx" || -n "$sysmsg" ]] || return 0
  local __hu_ee __hu_ec __hu_es out="{"
  if [[ -n "$ctx" ]]; then
    hook::json_escape_to __hu_ee "$event"
    hook::json_escape_to __hu_ec "$ctx"
    out+='"hookSpecificOutput":{"hookEventName":"'"$__hu_ee"'","additionalContext":"'"$__hu_ec"'"}'
    [[ -n "$sysmsg" ]] && out+=","
  fi
  if [[ -n "$sysmsg" ]]; then
    hook::json_escape_to __hu_es "$sysmsg"
    out+='"systemMessage":"'"$__hu_es"'"'
  fi
  out+="}"
  hook::emit_document "$out"
}

hook::emit_document() {
  printf '%s\n' "$1"
}

hook::emit_skip_notice() {
  local event="$1" model="$2" user="${3-$2}" probe=$'\nPATH probed: ' path=""
  if [[ "$model" == *"$probe"* ]]; then
    path="${model#*"$probe"}"
    model="${model%%"$probe"*}"
  fi
  if [[ "$user" == *"$probe"* ]]; then
    path="${user#*"$probe"}"
    user="${user%%"$probe"*}"
  fi
  [[ -n "$path" ]] && printf 'PATH probed: %s\n' "$path" >&2
  [[ "${HOOK_NOTICE_TO_MODEL:-1}" == 1 ]] || model=""
  [[ "${HOOK_NOTICE_TO_USER:-1}" == 1 ]] || user=""
  HOOK_NOTICE_TO_MODEL=1
  HOOK_NOTICE_TO_USER=1
  hook::emit_channels "$event" "$model" "$user"
}

hook::stdin_cut_short_notice() {
  local msg="$2: hook stdin was cut short, so this tool call ran unchecked. If it recurs, the host is starved; see the stdin_read_timeout option."
  echo "$msg" >&2
  hook::emit_channels "" "" "$msg"
}

# systemMessage-only variant for a hook with nothing for the model. Notification
# hooks do not use it, per https://code.claude.com/docs/en/hooks#notification.
hook::emit_system_message() {
  hook::emit_channels "" "" "$1"
}

hook::session_agent_to() {
  local __hu_sa_s="no-session" __hu_sa_a="no-agent"
  if [[ "$3" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    __hu_sa_s="${BASH_REMATCH[1]//[^A-Za-z0-9_-]/-}"
  fi
  if [[ "$3" =~ \"agent_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    __hu_sa_a="${BASH_REMATCH[1]}"
  elif [[ "$3" =~ \"transcript_path\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
    __hu_sa_a="${BASH_REMATCH[1]##*/}"
    __hu_sa_a="${__hu_sa_a%.jsonl}"
  fi
  __hu_sa_a="${__hu_sa_a//[^A-Za-z0-9_-]/-}"
  printf -v "$1" '%s' "$__hu_sa_s"
  printf -v "$2" '%s' "${__hu_sa_a:-no-agent}"
}

hook::_state_dir_to() {
  [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] || return 1
  local __hu_sd="${CLAUDE_PLUGIN_DATA%/}/$2"
  if [[ ! -d "$__hu_sd" ]]; then
    mkdir -p "$__hu_sd" 2>/dev/null || return 1
  fi
  local __hu_sd_var="_HOOK_PRUNED_${2//[^A-Za-z0-9_]/_}"
  if [[ -z "${!__hu_sd_var:-}" ]]; then
    find "$__hu_sd" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
    printf -v "$__hu_sd_var" '%s' 1
  fi
  printf -v "$1" '%s' "$__hu_sd"
}

hook::_file_key_to() {
  local __hu_fk="${2//[^A-Za-z0-9._-]/_}"
  ((${#__hu_fk} > 120)) && __hu_fk="${__hu_fk: -120}"
  printf -v "$1" '%s' "$__hu_fk"
}

hook::_claim() {
  (set -C && : >"$1") 2>/dev/null && return 0
  [[ -e "$1" ]] && return 1
  return 2
}

HOOK_NOTICE_TO_MODEL=1
HOOK_NOTICE_TO_USER=1
HOOK_NOTICE_KIND=full

# shellcheck disable=SC2034 # HOOK_NOTICE_KIND is read by callers, not here
hook::notice_once() {
  local key="$1" session agent dir
  HOOK_NOTICE_TO_MODEL=1
  HOOK_NOTICE_TO_USER=1
  HOOK_NOTICE_KIND=full
  hook::session_agent_to session agent "${2:-}"
  hook::_state_dir_to dir skip-notices || return 0
  local model="$dir/${key}.${session}.${agent}" user="$dir/${key}.${session}.user"
  hook::_claim "$model"
  case $? in 1) HOOK_NOTICE_TO_MODEL=0 ;; 2) return 0 ;; *) ;; esac
  hook::_claim "$user"
  case $? in 1) HOOK_NOTICE_TO_USER=0 ;; 2) return 0 ;; *) ;; esac
  if [[ "$HOOK_NOTICE_TO_USER" == 1 ]]; then
    return 0
  elif [[ "$HOOK_NOTICE_TO_MODEL" == 1 ]]; then
    HOOK_NOTICE_KIND=model
    return 0
  fi
  HOOK_NOTICE_KIND=silent
  HOOK_NOTICE_TO_MODEL=1
  HOOK_NOTICE_TO_USER=1
  return 1
}

hook::once_per_file() {
  local session agent dir fkey prev=""
  hook::session_agent_to session agent "$2"
  hook::_state_dir_to dir skip-notices || return 0
  hook::_file_key_to fkey "$3"
  local marker="$dir/${1}.${session}.${agent}.f.${fkey}"
  if [[ -f "$marker" ]]; then
    IFS= read -r prev <"$marker" || true
    [[ "$prev" == "$3" ]] && return 1
  fi
  printf '%s\n' "$3" 2>/dev/null >"$marker" || true
  return 0
}

hook::raw_file_path_to() {
  [[ "$2" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]] || return 1
  [[ -n "${BASH_REMATCH[1]}" ]] || return 1
  printf -v "$1" '%s' "${BASH_REMATCH[1]}"
}

hook::raw_file_path() {
  local __hu_raw
  hook::raw_file_path_to __hu_raw "$1" || return 1
  printf '%s' "$__hu_raw"
}

hook::require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  local model user
  if hook::prereq_notice_to model user "$1" "${4:-}" --label "$3" --no-path; then
    hook::emit_skip_notice "$2" "$model" "$user"
  fi
  exit 0
}

hook::prereq_notice_to() {
  local __hu_prn_m="$1" __hu_prn_u="$2" __hu_prn_id="$3" __hu_prn_in="$4"
  local __hu_prn_label="" __hu_prn_where="" __hu_prn_inst="" __hu_prn_inst_set=0 __hu_prn_path=1
  shift 4
  while (($#)); do
    case "$1" in
    --label) __hu_prn_label="$2" ;;
    --where) __hu_prn_where="$2" ;;
    --install)
      __hu_prn_inst="$2"
      __hu_prn_inst_set=1
      ;;
    --no-path)
      __hu_prn_path=0
      shift
      continue
      ;;
    *) ;;
    esac
    shift 2 || break
  done
  local __hu_prn_d __hu_prn_i __hu_prn_c __hu_prn_local __hu_prn_name
  hook::prerequisite_fields_to __hu_prn_d __hu_prn_i __hu_prn_c "$__hu_prn_id" __hu_prn_local __hu_prn_name
  [[ -n "$__hu_prn_label" ]] || __hu_prn_label="$__hu_prn_name"
  printf -v "$__hu_prn_m" '%s' ""
  printf -v "$__hu_prn_u" '%s' ""
  hook::notice_once "${__hu_prn_label}-${__hu_prn_id}" "$__hu_prn_in" || return 1
  if [[ -z "$__hu_prn_where" ]]; then
    __hu_prn_where="not on the hook PATH${__hu_prn_local:+ or at $__hu_prn_local}"
  fi
  ((__hu_prn_inst_set)) || __hu_prn_inst="${__hu_prn_i:+Install ($__hu_prn_i).}"
  local __hu_prn_head="$__hu_prn_label: $__hu_prn_id $__hu_prn_where. $__hu_prn_d"
  local __hu_prn_tail="No further notice this session; diagnose with: node \"${CLAUDE_PLUGIN_ROOT:-}/lib/prerequisites.mjs\" check \"${CLAUDE_PLUGIN_ROOT:-}\""
  ((__hu_prn_path)) && printf 'PATH probed: %s\n' "${PATH:-<unset>}" >&2
  [[ "$HOOK_NOTICE_TO_MODEL" == 1 ]] && printf -v "$__hu_prn_m" '%s' "$__hu_prn_head $__hu_prn_tail"
  [[ "$HOOK_NOTICE_TO_USER" == 1 ]] &&
    printf -v "$__hu_prn_u" '%s' "$__hu_prn_head ${__hu_prn_inst:+$__hu_prn_inst }Hooks read Claude Code's PATH, not your shell profile. $__hu_prn_tail"
  return 0
}

hook::prerequisite_fields_to() {
  local __hu_d="The hook skips its work." __hu_i="" __hu_c="" __hu_l=""
  local __hu_root="${CLAUDE_PLUGIN_ROOT:-}" __hu_txt="" __hu_name="" __hu_m
  local __hu_s='[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  if [[ -r "$__hu_root/prerequisites.json" ]]; then
    __hu_txt=$(<"$__hu_root/prerequisites.json")
    if [[ "$__hu_txt" =~ \"id\"[[:space:]]*:[[:space:]]*\"$4\"(.*) ]]; then
      __hu_txt="${BASH_REMATCH[1]}"
      __hu_txt="${__hu_txt%%\"id\"[[:space:]]*:*}"
      [[ "$__hu_txt" =~ \"degrade\"$__hu_s ]] && __hu_d="${BASH_REMATCH[1]}"
      [[ "$__hu_txt" =~ \"check\"$__hu_s ]] && __hu_c="${BASH_REMATCH[1]}"
      if [[ "$__hu_txt" =~ \"install\"[[:space:]]*:[[:space:]]*\{([^}]*)\} ]]; then
        __hu_m="${BASH_REMATCH[1]}"
        while [[ "$__hu_m" =~ \"([^\"]+)\"$__hu_s(.*) ]]; do
          __hu_i+="${__hu_i:+; }${BASH_REMATCH[1]}: ${BASH_REMATCH[2]}"
          __hu_m="${BASH_REMATCH[4]}"
        done
      fi
      if [[ "$__hu_txt" =~ \"local_bin\"[[:space:]]*:[[:space:]]*\[([^]]*)\] ]]; then
        __hu_m="${BASH_REMATCH[1]}"
        while [[ "$__hu_m" =~ \"(([^\"\\]|\\.)*)\"(.*) ]]; do
          __hu_l+="${__hu_l:+ or }${BASH_REMATCH[1]}"
          __hu_m="${BASH_REMATCH[3]}"
        done
      fi
      __hu_d="${__hu_d//\\\"/\"}"
    fi
  fi
  if [[ -r "$__hu_root/.claude-plugin/plugin.json" ]] &&
    [[ "$(<"$__hu_root/.claude-plugin/plugin.json")" =~ \"name\"$__hu_s ]]; then
    __hu_name="${BASH_REMATCH[1]}"
  else
    __hu_name="${__hu_root%/}"
    __hu_name="${__hu_name##*/}"
    if [[ "$__hu_name" =~ ^[0-9] ]]; then
      __hu_name="${__hu_root%/*}"
      __hu_name="${__hu_name##*/}"
    fi
  fi
  __hu_name="${__hu_name:-plugin}"
  if [[ -z "$__hu_c" ]]; then
    __hu_c="/${__hu_name}:check"
    [[ -d "$__hu_root/skills/check-prerequisites" ]] && __hu_c+="-prerequisites"
  fi
  printf -v "$1" '%s' "$__hu_d"
  printf -v "$2" '%s' "$__hu_i"
  printf -v "$3" '%s' "$__hu_c"
  [[ -n "${5:-}" ]] && printf -v "$5" '%s' "$__hu_l"
  [[ -n "${6:-}" ]] && printf -v "$6" '%s' "$__hu_name"
  return 0
}

hook::require_jq_blocking() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "BLOCKED: jq is not on PATH, so $1 cannot read the command and denies every Bash and PowerShell call. Ask the user to install jq (https://jqlang.org/download/)." >&2
  exit 2
}

hook::normalize_path_to() {
  local __hu_p="${2//\\//}"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    if [[ "$__hu_p" =~ ^/([a-zA-Z])/ || "$__hu_p" =~ ^([a-zA-Z]):/ ]]; then
      local __hu_rest="${__hu_p:2}"
      printf -v "$1" '%s' "${BASH_REMATCH[1]^}:${__hu_rest,,}"
      return 0
    fi
    ;;
  *) ;; # POSIX hosts: case-sensitive FS, no drive fold — pass through below
  esac
  printf -v "$1" '%s' "$__hu_p"
}

hook::expand_8dot3_to() {
  local __hu_p="$2"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32) ;;
  *)
    printf -v "$1" '%s' "$__hu_p"
    return 0
    ;;
  esac
  if [[ "$__hu_p" == *~* ]] && command -v cygpath >/dev/null 2>&1; then
    local __hu_plain __hu_long
    if __hu_plain=$(cygpath -m -- "$__hu_p" 2>/dev/null) &&
      __hu_long=$(cygpath -l -m -- "$__hu_p" 2>/dev/null) &&
      [[ -n "$__hu_long" && "$__hu_long" != "$__hu_plain" ]]; then
      printf -v "$1" '%s' "$__hu_long"
      return 0
    fi
  fi
  printf -v "$1" '%s' "$__hu_p"
}

hook::_physical_builtin_to() {
  [[ "${OSTYPE:-}" == linux* ]] || return 1
  local __hu_pb_dest="$1" __hu_pb_p __hu_pb_out
  shift
  for __hu_pb_p in "$@"; do
    [[ "$__hu_pb_p" == /* && "$__hu_pb_p" != *//* && "$__hu_pb_p" != *$'\n'* ]] || return 1
  done
  __hu_pb_out=$(
    for __hu_pb_p in "$@"; do
      if [[ -d "$__hu_pb_p" ]]; then
        builtin cd -P -- "$__hu_pb_p" 2>/dev/null || exit 1
        printf '%s\n' "$PWD"
      else
        [[ -e "$__hu_pb_p" && ! -L "$__hu_pb_p" ]] || exit 1
        __hu_pb_d=${__hu_pb_p%/*} __hu_pb_b=${__hu_pb_p##*/}
        [[ -n "$__hu_pb_b" && "$__hu_pb_b" != . && "$__hu_pb_b" != .. ]] || exit 1
        builtin cd -P -- "${__hu_pb_d:-/}" 2>/dev/null || exit 1
        printf '%s\n' "${PWD%/}/$__hu_pb_b"
      fi
    done
  ) || return 1
  printf -v "$__hu_pb_dest" '%s' "$__hu_pb_out"
}

# shellcheck disable=SC2034  # public contract: advisory callers may read HOOK_PHYSICAL_PATH_UNRESOLVED
hook::physical_path_to() {
  local __hu_r=""
  HOOK_PHYSICAL_PATH_UNRESOLVED=0
  if hook::_physical_builtin_to __hu_r "$2"; then
    hook::expand_8dot3_to "$1" "$__hu_r"
    return 0
  fi
  if __hu_r=$(realpath -- "$2" 2>/dev/null) || __hu_r=$(readlink -f -- "$2" 2>/dev/null); then
    if [[ -n "$__hu_r" ]]; then
      hook::expand_8dot3_to "$1" "$__hu_r"
      return 0
    fi
  fi
  HOOK_PHYSICAL_PATH_UNRESOLVED=1
  printf -v "$1" '%s' "$2"
  return 1
}

# shellcheck disable=SC2034  # public contract: advisory callers may read HOOK_PHYSICAL_PATH_UNRESOLVED
hook::physical_path() {
  local __hu_v __hu_rc=0
  hook::physical_path_to __hu_v "$1" || __hu_rc=$?
  printf '%s' "$__hu_v"
  return "$__hu_rc"
}

# Parallel indexed arrays: associative arrays need bash 4.0, and this library supports 3.2:
# https://tiswww.case.edu/php/chet/bash/NEWS
_HOOK_PHYS_KEYS=()
_HOOK_PHYS_VALS=()
_HOOK_PHYS_RCS=()
_HOOK_PHYS_I=-1

hook::_phys_cache_index() {
  local __hu_i
  [[ -n "$1" ]] || return 1
  for ((__hu_i = 0; __hu_i < ${#_HOOK_PHYS_KEYS[@]}; __hu_i++)); do
    if [[ "${_HOOK_PHYS_KEYS[__hu_i]}" == "$1" ]]; then
      _HOOK_PHYS_I=$__hu_i
      return 0
    fi
  done
  return 1
}

hook::_phys_cache_forget() {
  hook::_phys_cache_index "$1" && _HOOK_PHYS_KEYS[_HOOK_PHYS_I]=""
  return 0
}

# shellcheck disable=SC2034  # public contract: advisory callers may read HOOK_PHYSICAL_PATH_UNRESOLVED
hook::_physical_cached_to() {
  if hook::_phys_cache_index "$2"; then
    printf -v "$1" '%s' "${_HOOK_PHYS_VALS[_HOOK_PHYS_I]}"
    HOOK_PHYSICAL_PATH_UNRESOLVED=${_HOOK_PHYS_RCS[_HOOK_PHYS_I]}
    return "${_HOOK_PHYS_RCS[_HOOK_PHYS_I]}"
  fi
  local __hu_v __hu_rc=0
  hook::physical_path_to __hu_v "$2" || __hu_rc=$?
  if [[ -n "$2" ]]; then
    _HOOK_PHYS_KEYS+=("$2")
    _HOOK_PHYS_VALS+=("$__hu_v")
    _HOOK_PHYS_RCS+=("$__hu_rc")
  fi
  printf -v "$1" '%s' "$__hu_v"
  return "$__hu_rc"
}

hook::_physical_prime() {
  local -a __hu_todo=()
  local __hu_p __hu_out __hu_i __hu_seen="" __hu_v
  for __hu_p in "$@"; do
    [[ -n "$__hu_p" ]] || continue
    [[ "$__hu_p" == *$'\n'* ]] && return 0
    case "$__hu_seen" in
    *"|$__hu_p|"*) continue ;;
    *) ;; # first sighting
    esac
    __hu_seen="$__hu_seen|$__hu_p|"
    hook::_phys_cache_index "$__hu_p" && continue
    __hu_todo+=("$__hu_p")
  done
  ((${#__hu_todo[@]} > 1)) || return 0
  if ! hook::_physical_builtin_to __hu_out "${__hu_todo[@]}"; then
    command -v realpath >/dev/null 2>&1 || return 0
    # portability-ok: realpath with several operands is GNU and BSD alike; a host whose realpath rejects it fails the exit-status check and falls back per path
    __hu_out=$(realpath -- "${__hu_todo[@]}" 2>/dev/null) || return 0
  fi
  local -a __hu_lines=()
  hook::_split_lines "$__hu_out" "${#__hu_todo[@]}" || return 0
  for ((__hu_i = 0; __hu_i < ${#__hu_todo[@]}; __hu_i++)); do
    hook::expand_8dot3_to __hu_v "${__hu_lines[__hu_i]}"
    _HOOK_PHYS_KEYS+=("${__hu_todo[__hu_i]}")
    _HOOK_PHYS_VALS+=("$__hu_v")
    _HOOK_PHYS_RCS+=(0)
  done
  return 0
}

_HOOK_TEMP_CANDS=()
_HOOK_TEMP_WIN_KEY=""
_HOOK_TEMP_WIN=()
hook::_temp_root_candidates() {
  local __hu_cand __hu_seen=""
  _HOOK_TEMP_CANDS=()
  for __hu_cand in "${TMPDIR:-}" "${TMP:-}" "${TEMP:-}" /tmp /var/tmp; do
    [[ -n "$__hu_cand" && -d "$__hu_cand" ]] || continue
    case "$__hu_seen" in
    *"|$__hu_cand|"*) continue ;;
    *) ;; # first sighting of this candidate
    esac
    __hu_seen="$__hu_seen|$__hu_cand|"
    _HOOK_TEMP_CANDS+=("$__hu_cand")
  done
  [[ "${1:-}" == --no-drive ]] && return 0
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32) ;;
  *) return 0 ;; # POSIX hosts: the candidates above are the whole set
  esac
  ((${#_HOOK_TEMP_CANDS[@]})) || return 0
  if [[ "$_HOOK_TEMP_WIN_KEY" != "$__hu_seen" ]]; then
    hook::_temp_win_spellings "${_HOOK_TEMP_CANDS[@]}" || return 0
    _HOOK_TEMP_WIN_KEY=$__hu_seen
  fi
  for __hu_cand in ${_HOOK_TEMP_WIN[@]+"${_HOOK_TEMP_WIN[@]}"}; do
    [[ -n "$__hu_cand" && -d "$__hu_cand" ]] || continue
    case "$__hu_seen" in
    *"|$__hu_cand|"*) continue ;;
    *) ;; # first sighting of this spelling
    esac
    __hu_seen="$__hu_seen|$__hu_cand|"
    _HOOK_TEMP_CANDS+=("$__hu_cand")
  done
}

hook::_split_lines() {
  local __hu_glob=0 IFS=$'\n'
  [[ $- == *f* ]] || __hu_glob=1
  set -f
  # shellcheck disable=SC2206 # splitting one-line-per-operand output is the intent
  __hu_lines=($1)
  ((__hu_glob)) && set +f
  ((${#__hu_lines[@]} == $2))
}

hook::_temp_win_spellings() {
  local __hu_out __hu_i
  local -a __hu_lines=() __hu_mixed=() __hu_tilde=()
  command -v cygpath >/dev/null 2>&1 || return 1
  for __hu_out in "$@"; do
    [[ "$__hu_out" == *$'\n'* ]] && return 1
  done
  __hu_out=$(cygpath -m -- "$@" 2>/dev/null) || return 1
  hook::_split_lines "$__hu_out" "$#" || return 1
  __hu_mixed=("${__hu_lines[@]}")
  _HOOK_TEMP_WIN=()
  for __hu_out in "${__hu_mixed[@]}"; do
    if [[ "$__hu_out" == *~* ]]; then __hu_tilde+=("$__hu_out"); fi
  done
  if ((${#__hu_tilde[@]})) &&
    __hu_out=$(cygpath -l -m -- "${__hu_tilde[@]}" 2>/dev/null) &&
    hook::_split_lines "$__hu_out" "${#__hu_tilde[@]}"; then
    for ((__hu_i = 0; __hu_i < ${#__hu_tilde[@]}; __hu_i++)); do
      if [[ "${__hu_lines[__hu_i]}" != "${__hu_tilde[__hu_i]}" ]]; then
        _HOOK_TEMP_WIN+=("${__hu_lines[__hu_i]}")
      fi
    done
  fi
  _HOOK_TEMP_WIN+=("${__hu_mixed[@]}")
}

_HOOK_UTR_TARGET_PHYSICAL=0
hook::under_temp_root() {
  local target="$1" cand norm phys
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32) hook::normalize_path_to target "$target" ;;
  *) ;; # POSIX hosts: compare the target as given
  esac
  hook::_temp_root_candidates
  for cand in ${_HOOK_TEMP_CANDS[@]+"${_HOOK_TEMP_CANDS[@]}"}; do
    if ((_HOOK_UTR_TARGET_PHYSICAL)); then
      hook::normalize_path_to norm "$cand"
      if [[ "$norm" != / ]]; then
        norm="${norm%/}"
        if [[ -n "$norm" && ("$target" == "$norm" || "$target" == "$norm"/*) ]]; then
          return 0
        fi
      fi
    fi
    hook::_physical_cached_to phys "$cand" || :
    hook::normalize_path_to norm "$phys"
    [[ "$norm" == / ]] && return 0
    norm="${norm%/}"
    [[ -n "$norm" ]] || continue
    [[ "$target" == "$norm" || "$target" == "$norm"/* ]] && return 0
  done
  return 1
}

hook::in_git_working_tree() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM
    git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$1" rev-parse --show-toplevel
  ) >/dev/null 2>&1
}

HOOK_GIT_UNTRUSTED_CONFIG=(core.fsmonitor=false core.hooksPath=/dev/null)
_HOOK_GIT_UNTRUSTED_ARGS=(--no-pager)
for __hu_kv in "${HOOK_GIT_UNTRUSTED_CONFIG[@]}"; do _HOOK_GIT_UNTRUSTED_ARGS+=(-c "$__hu_kv"); done
unset __hu_kv
# git -c overrides the repository's config files, so these keys stay off whatever it sets:
# https://git-scm.com/docs/git#Documentation/git.txt--cltnamegtltvaluegt
hook::git_untrusted() {
  git "${_HOOK_GIT_UNTRUSTED_ARGS[@]}" "$@"
}

hook::git_untrusted_exec() {
  exec git "${_HOOK_GIT_UNTRUSTED_ARGS[@]}" "$@"
}

hook::git_untrusted_env() {
  local n="${GIT_CONFIG_COUNT:-0}" kv
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    printf '%s: cannot run the end-of-turn check: GIT_CONFIG_COUNT is not a number\n' "${0##*/}" >&2
    return 1
  fi
  n=$((10#$n))
  for kv in "${HOOK_GIT_UNTRUSTED_CONFIG[@]}"; do
    export "GIT_CONFIG_KEY_$n=${kv%%=*}" "GIT_CONFIG_VALUE_$n=${kv#*=}"
    n=$((n + 1))
  done
  export GIT_CONFIG_COUNT="$n"
}

hook::file_is_gitignored() {
  local file="$1" dir base
  dir="${file%/*}" base="${file##*/}"
  command -v git >/dev/null 2>&1 || return 1
  [[ -n "$base" && "$dir" != "$file" ]] || return 1
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM
    cd "${dir:-/}" 2>/dev/null || exit 1
    hook::git_untrusted check-ignore -q -- "./$base" 2>/dev/null
  )
}

hook::gitignored_out_of_scope() {
  [[ "$1" == "true" ]] && return 1
  hook::file_is_gitignored "$2"
}

hook::_c_locale() {
  local __hu_lc_set=${LC_ALL+x} __hu_lc=${LC_ALL-} __hu_lc_rc=0
  LC_ALL=C
  "$@" || __hu_lc_rc=$?
  if [[ -n "$__hu_lc_set" ]]; then LC_ALL=$__hu_lc; else unset LC_ALL; fi
  return "$__hu_lc_rc"
}

_HOOK_JSON_PARTS=()
_HOOK_JSON_NT=""
hook::_json_split() {
  local __hu_s="$1" __hu_t __hu_q __hu_n
  ((${#__hu_s} <= 65536)) || return 1
  __hu_t=${__hu_s//"\\\\"/@@}
  __hu_t=${__hu_t//"\\\""/@@}
  _HOOK_JSON_NT=$__hu_t
  __hu_q=${__hu_t//\"/}
  __hu_n=$((${#__hu_t} - ${#__hu_q}))
  ((__hu_n % 2 == 0)) || return 1
  ((__hu_n <= 2000)) || return 1
  local __hu_glob=0
  [[ $- == *f* ]] || __hu_glob=1
  set -f
  local IFS='"'
  # shellcheck disable=SC2206 # splitting on IFS='"' is the whole point
  _HOOK_JSON_PARTS=($__hu_t)
  ((__hu_glob)) && set +f
  ((${#_HOOK_JSON_PARTS[@]} % 2 == 1)) || return 1
  return 0
}

_HOOK_JSON_SK=""
_HOOK_JSON_OFF=()
_HOOK_JSON_SK_TEXT=""
_HOOK_JSON_SK_RC=""
hook::_json_skeleton() {
  local __hu_s="$1" __hu_i __hu_n __hu_part __hu_off=0 __hu_sk="" __hu_g="" __hu_prev __hu_esc __hu_c
  local __hu_rx=1 __hu_partcntrl=1
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32) __hu_rx=0 ;;
  *) ;;
  esac
  local __hu_cntrl='[[:cntrl:]]'
  local __hu_badesc='\\([^/bfnrtu]|$|u(.?.?.?$|[^0-9a-fA-F]|.[^0-9a-fA-F]|..[^0-9a-fA-F]|...[^0-9a-fA-F]))'
  if [[ -n "$_HOOK_JSON_SK_RC" && "$__hu_s" == "$_HOOK_JSON_SK_TEXT" ]]; then
    return "$_HOOK_JSON_SK_RC"
  fi
  _HOOK_JSON_SK_TEXT=$__hu_s
  _HOOK_JSON_SK_RC=1
  hook::_json_split "$__hu_s" || return 1
  if ((__hu_rx)); then
    [[ "$_HOOK_JSON_NT" =~ $__hu_badesc ]] && return 1
    [[ "$__hu_s" =~ $__hu_cntrl ]] || __hu_partcntrl=0
  fi
  __hu_n=${#_HOOK_JSON_PARTS[@]}
  _HOOK_JSON_OFF=()
  for ((__hu_i = 0; __hu_i < __hu_n; __hu_i++)); do
    __hu_part=${_HOOK_JSON_PARTS[__hu_i]}
    if ((__hu_i % 2 == 0)); then
      __hu_sk+=$__hu_part
      __hu_g+=$__hu_part
    else
      _HOOK_JSON_OFF[__hu_i]=$__hu_off
      if ((__hu_rx)); then
        ((__hu_partcntrl)) && [[ "$__hu_part" =~ $__hu_cntrl ]] && return 1
      else
        [[ "$__hu_part" == *[[:cntrl:]]* ]] && return 1
        if [[ "$__hu_part" == *\\* ]]; then
          __hu_esc=${__hu_part//'\u'[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/}
          for __hu_c in / b f n r t; do
            __hu_esc=${__hu_esc//"\\$__hu_c"/}
          done
          [[ "$__hu_esc" == *\\* ]] && return 1
        fi
      fi
      __hu_sk+="\"#$__hu_i\""
      __hu_g+='"'
    fi
    __hu_off=$((__hu_off + ${#__hu_part} + 1))
  done
  local __hu_ws=$' \t\n\r'
  local __hu_wsre="[^][{}:,$__hu_ws][$__hu_ws]+[^][{}:,$__hu_ws]"
  [[ "$__hu_g" =~ $__hu_wsre ]] && return 1
  __hu_g=${__hu_g//[$__hu_ws]/}
  local __hu_sc=${__hu_g//[][\{\}:,]/ }
  local __hu_scre='^ *(("|true|false|null|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?) +)*$'
  [[ "$__hu_sc " =~ $__hu_scre ]] || return 1
  ((${#__hu_g} <= 8192)) || return 1
  __hu_g=${__hu_g//[^\]\[\{\}:,\"]/v}
  while [[ "$__hu_g" == *vv* ]]; do __hu_g=${__hu_g//vv/v}; done
  __hu_g="<k:${__hu_g//\"/s}>"
  __hu_g=${__hu_g//s,/v,}
  __hu_g=${__hu_g//s\]/v]}
  __hu_g=${__hu_g//s\}/v\}}
  __hu_g=${__hu_g//s>/v>}
  while :; do
    __hu_prev=$__hu_g
    __hu_g=${__hu_g//k:v/K}
    __hu_g=${__hu_g//s:v/m}
    while [[ "$__hu_g" == *v,v* ]]; do __hu_g=${__hu_g//v,v/v}; done
    while [[ "$__hu_g" == *m,m* ]]; do __hu_g=${__hu_g//m,m/m}; done
    __hu_g=${__hu_g//\{m\}/v}
    __hu_g=${__hu_g//\{\}/v}
    __hu_g=${__hu_g//\[v\]/v}
    __hu_g=${__hu_g//\[\]/v}
    [[ "$__hu_g" != "$__hu_prev" ]] || break
  done
  [[ "$__hu_g" == '<K>' ]] || return 1
  _HOOK_JSON_SK=${__hu_sk//[$' \t\n\r']/}
  _HOOK_JSON_SK_RC=0
  return 0
}

hook::_json_object_proven() {
  [[ "${LC_ALL-}" == C ]] || {
    hook::_c_locale hook::_json_object_proven "$@"
    return
  }
  hook::_json_skeleton "$1" && [[ "$_HOOK_JSON_SK" == \{* ]]
}

hook::json_unescape_to() {
  local __hu_raw="$2" __hu_out="" __hu_pre __hu_c __hu_hex __hu_oct __hu_ch
  while [[ "$__hu_raw" == *\\* ]]; do
    __hu_pre=${__hu_raw%%\\*}
    __hu_out+=$__hu_pre
    __hu_raw=${__hu_raw:${#__hu_pre}+1}
    __hu_c=${__hu_raw:0:1}
    __hu_raw=${__hu_raw:1}
    case "$__hu_c" in
    '"') __hu_out+='"' ;;
    "\\") __hu_out+="\\" ;;
    '/') __hu_out+='/' ;;
    b) __hu_out+=$'\b' ;; # portability-ok: bash ANSI-C backspace byte, not a GNU grep word boundary
    f) __hu_out+=$'\f' ;;
    n) __hu_out+=$'\n' ;;
    r) __hu_out+=$'\r' ;;
    t) __hu_out+=$'\t' ;;
    u)
      __hu_hex=${__hu_raw:0:4}
      [[ "$__hu_hex" =~ ^00[0-7][0-9a-fA-F]$ ]] || return 1
      [[ "$__hu_hex" == 0000 ]] && return 1
      __hu_raw=${__hu_raw:4}
      printf -v __hu_oct '%03o' "$((16#$__hu_hex))"
      printf -v __hu_ch '%b' "\\0$__hu_oct"
      __hu_out+=$__hu_ch
      ;;
    *) return 1 ;;
    esac
  done
  __hu_out+=$__hu_raw
  printf -v "$1" '%s' "$__hu_out"
}

hook::_key_depth_is_one() {
  local __hu_pre=${_HOOK_JSON_SK%%\"#"$1"\"*}
  local __hu_open=${__hu_pre//[^\{\[]/} __hu_close=${__hu_pre//[^\}\]]/}
  ((${#__hu_open} - ${#__hu_close} == 1))
}

hook::_fast_file_path_to() {
  [[ "${LC_ALL-}" == C ]] || {
    hook::_c_locale hook::_fast_file_path_to "$@"
    return
  }
  local __hu_s="$2" __hu_i __hu_n __hu_part __hu_body __hu_ti=-1 __hu_fp=-1 __hu_m __hu_re __hu_file
  hook::_json_skeleton "$__hu_s" || return 2
  [[ "$_HOOK_JSON_SK" == \{* ]] || return 2
  __hu_n=${#_HOOK_JSON_PARTS[@]}
  for ((__hu_i = 1; __hu_i < __hu_n; __hu_i += 2)); do
    __hu_part=${_HOOK_JSON_PARTS[__hu_i]}
    ((${#__hu_part} <= 60)) || continue
    if [[ "$__hu_part" == *@* ]]; then
      __hu_body=${__hu_s:${_HOOK_JSON_OFF[__hu_i]}:${#__hu_part}}
    else
      __hu_body=$__hu_part
    fi
    if [[ "$__hu_body" == *\\* ]]; then
      hook::json_unescape_to __hu_body "$__hu_body" || continue
    fi
    case "$__hu_body" in
    tool_input)
      ((__hu_ti < 0)) || return 2
      __hu_ti=$__hu_i
      ;;
    file_path)
      ((__hu_fp < 0)) || return 2
      __hu_fp=$__hu_i
      ;;
    *) ;;
    esac
  done
  ((__hu_fp >= 0)) || return 1
  ((__hu_ti >= 0)) || return 1
  __hu_re="(^|[{,])\"#$__hu_ti\":\\{([^][{}]*)\\}"
  [[ "$_HOOK_JSON_SK" =~ $__hu_re ]] || return 2
  __hu_body=${BASH_REMATCH[2]}
  hook::_key_depth_is_one "$__hu_ti" || return 2
  __hu_re="(^|,)\"#$__hu_fp\":\"#([0-9]+)\"(,|$)"
  if [[ "$__hu_body" =~ $__hu_re ]]; then
    __hu_m=${BASH_REMATCH[2]}
  elif [[ "$__hu_body" == *\"#$__hu_fp\"* ]]; then
    return 2
  else
    return 1
  fi
  __hu_file=${__hu_s:${_HOOK_JSON_OFF[__hu_m]}:${#_HOOK_JSON_PARTS[__hu_m]}}
  if [[ "$__hu_file" == *\\* ]]; then
    hook::json_unescape_to __hu_file "$__hu_file" || return 2
  fi
  __hu_file=${__hu_file//$'\r'/}
  while [[ "$__hu_file" == *$'\n' ]]; do
    __hu_file=${__hu_file%$'\n'}
  done
  printf -v "$1" '%s' "$__hu_file"
  return 0
}

# hook::_fast_fields indexes with local -A, and associative arrays need bash 4.0:
# https://tiswww.case.edu/php/chet/bash/NEWS
hook::_fast_fields_supported() {
  ((BASH_VERSINFO[0] >= 4))
}

hook::_fast_fields() {
  [[ "${LC_ALL-}" == C ]] || {
    hook::_c_locale hook::_fast_fields "$@"
    return
  }
  local __hu_s="$1"
  shift
  local -a __hu_k1=() __hu_k2=() __hu_df=()
  local __hu_f __hu_i __hu_n __hu_part __hu_body __hu_re __hu_raw __hu_val __hu_j __hu_nil
  local __hu_ident='[A-Za-z_][A-Za-z0-9_]*'
  local __hu_cap=0
  __hu_re="^\\.($__hu_ident)(\\.($__hu_ident))?( // false \\| tostring)?\$"
  for __hu_f in "$@"; do
    [[ "$__hu_f" =~ $__hu_re ]] || return 2
    __hu_k1+=("${BASH_REMATCH[1]}")
    __hu_k2+=("${BASH_REMATCH[3]}")
    __hu_df+=("${BASH_REMATCH[4]:+1}")
    ((${#BASH_REMATCH[1]} > __hu_cap)) && __hu_cap=${#BASH_REMATCH[1]}
    ((${#BASH_REMATCH[3]} > __hu_cap)) && __hu_cap=${#BASH_REMATCH[3]}
  done
  __hu_cap=$((__hu_cap * 6))
  hook::_json_skeleton "$__hu_s" || return 2
  [[ "$_HOOK_JSON_SK" == \{* ]] || return 2
  local -A __hu_idx=()
  local -A __hu_want=()
  for __hu_f in "${__hu_k1[@]}" "${__hu_k2[@]}"; do
    [[ -n "$__hu_f" ]] && __hu_want[$__hu_f]=1
  done
  __hu_n=${#_HOOK_JSON_PARTS[@]}
  for ((__hu_i = 1; __hu_i < __hu_n; __hu_i += 2)); do
    __hu_part=${_HOOK_JSON_PARTS[__hu_i]}
    ((${#__hu_part} <= __hu_cap)) || continue
    if [[ "$__hu_part" == *@* ]]; then
      __hu_body=${__hu_s:${_HOOK_JSON_OFF[__hu_i]}:${#__hu_part}}
    else
      __hu_body=$__hu_part
    fi
    if [[ "$__hu_body" == *\\* ]]; then
      hook::json_unescape_to __hu_body "$__hu_body" || continue
    fi
    [[ -n "$__hu_body" && -n "${__hu_want[$__hu_body]+x}" ]] || continue
    if [[ -n "${__hu_idx[$__hu_body]+x}" ]]; then
      __hu_idx[$__hu_body]=-1
    else
      __hu_idx[$__hu_body]=$__hu_i
    fi
  done
  local -a __hu_vals=()
  local __hu_ti __hu_fi __hu_tok
  for ((__hu_j = 0; __hu_j < ${#__hu_k1[@]}; __hu_j++)); do
    __hu_nil=${__hu_df[__hu_j]:+false}
    __hu_ti=${__hu_idx[${__hu_k1[__hu_j]}]--2}
    ((__hu_ti != -1)) || return 2
    if ((__hu_ti == -2)); then
      __hu_vals+=("$__hu_nil") # no string in the payload spells the key: absent
      continue
    fi
    __hu_re="(^|[{,])\"#$__hu_ti\":(\"#[0-9]+\"|\\{[^][{}]*\\}|null|true|false|[-0-9][^,}]*|\\[|\\{)"
    if ! [[ "$_HOOK_JSON_SK" =~ $__hu_re ]]; then
      __hu_vals+=("$__hu_nil")
      continue
    fi
    __hu_tok=${BASH_REMATCH[2]}
    if ! hook::_key_depth_is_one "$__hu_ti"; then
      __hu_vals+=("$__hu_nil")
      continue
    fi
    if [[ -n "${__hu_k2[__hu_j]}" ]]; then
      case "$__hu_tok" in
      null) __hu_vals+=("$__hu_nil") && continue ;;
      \{*\}) ;;      # a flat object: its members are the only place the key can be
      *) return 2 ;; # a string, number, boolean, array, or an object with a container inside
      esac
      __hu_fi=${__hu_idx[${__hu_k2[__hu_j]}]--2}
      ((__hu_fi != -1)) || return 2
      if ((__hu_fi == -2)); then
        __hu_vals+=("$__hu_nil")
        continue
      fi
      __hu_body=${__hu_tok:1:${#__hu_tok}-2}
      __hu_re="(^|,)\"#$__hu_fi\":(\"#[0-9]+\"|null|true|false|[-0-9][^,]*)(,|\$)"
      if ! [[ "$__hu_body" =~ $__hu_re ]]; then
        __hu_vals+=("$__hu_nil") # not a key of the parent; unique, so not one anywhere
        continue
      fi
      __hu_tok=${BASH_REMATCH[2]}
    fi
    case "$__hu_tok" in
    \"#*) __hu_raw=${__hu_tok:2:${#__hu_tok}-3} ;;
    null) __hu_vals+=("$__hu_nil") && continue ;;
    true | false)
      [[ -n "${__hu_df[__hu_j]}" ]] || return 2
      __hu_vals+=("$__hu_tok") && continue
      ;;
    *) return 2 ;; # a number, an object or an array: jq's tostring
    esac
    __hu_val=${__hu_s:${_HOOK_JSON_OFF[__hu_raw]}:${#_HOOK_JSON_PARTS[__hu_raw]}}
    if [[ "$__hu_val" == *\\* ]]; then
      hook::json_unescape_to __hu_val "$__hu_val" || return 2
    fi
    __hu_val=${__hu_val//$'\r'/}
    __hu_vals+=("$__hu_val")
  done
  HOOK_JQ_FIELDS=("${__hu_vals[@]}")
  HOOK_JQ_FIELDS_NUL=0
  return 0
}

hook::dirname_to() {
  local __hu_d="${2%/*}"
  [[ "$__hu_d" == "$2" ]] && __hu_d=.
  [[ -n "$__hu_d" ]] || __hu_d=/
  printf -v "$1" '%s' "$__hu_d"
}

hook::_print_nul_joined() {
  local __hu_first=1 __hu_c
  for __hu_c in "$@"; do
    ((__hu_first)) || printf '\0'
    __hu_first=0
    printf '%s' "$__hu_c"
  done
}

hook::json_compact_to() {
  [[ "${LC_ALL-}" == C ]] || {
    hook::_c_locale hook::json_compact_to "$@"
    return
  }
  local __hu_s="$2" __hu_out="" __hu_i __hu_part __hu_n
  hook::_json_skeleton "$__hu_s" || return 1
  [[ "$_HOOK_JSON_SK" == \{*\} ]] || return 1
  local __hu_num='[0-9][.eE]|[0-9]{16}'
  [[ "$_HOOK_JSON_SK" =~ $__hu_num ]] && return 1
  __hu_n=${#_HOOK_JSON_PARTS[@]}
  for ((__hu_i = 0; __hu_i < __hu_n; __hu_i++)); do
    __hu_part=${_HOOK_JSON_PARTS[__hu_i]}
    if ((__hu_i % 2 == 0)); then
      __hu_out+=${__hu_part//[$' \t\n\r']/}
    else
      if [[ "$__hu_part" == *\\* ]]; then
        [[ "$__hu_part" == *'\u'* || "$__hu_part" == *'\/'* ]] && return 1
        [[ "$__hu_part" == *\\[!bfnrt]* ]] && return 1
      fi
      __hu_out+="\"${__hu_s:${_HOOK_JSON_OFF[__hu_i]}:${#__hu_part}}\""
    fi
  done
  printf -v "$1" '%s' "$__hu_out"
}

hook::json_escape_jq_to() {
  local __hu_s="$2" __hu_i __hu_c __hu_oct __hu_hex
  __hu_s="${__hu_s//\\/\\\\}"
  __hu_s="${__hu_s//\"/\\\"}"
  if [[ "$__hu_s" == *[[:cntrl:]]* ]]; then
    __hu_s="${__hu_s//$'\n'/\\n}"
    __hu_s="${__hu_s//$'\r'/\\r}"
    __hu_s="${__hu_s//$'\t'/\\t}"
    __hu_s="${__hu_s//$'\b'/\\b}" # portability-ok: bash ANSI-C backspace byte and the JSON \b escape, not a GNU grep word boundary
    __hu_s="${__hu_s//$'\f'/\\f}"
    for __hu_i in 1 2 3 4 5 6 7 11 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
      printf -v __hu_oct '%03o' "$__hu_i"
      printf -v __hu_c '%b' "\\0$__hu_oct"
      [[ "$__hu_s" == *"$__hu_c"* ]] || continue
      printf -v __hu_hex '%04x' "$__hu_i"
      __hu_s="${__hu_s//"$__hu_c"/\\u$__hu_hex}"
    done
  fi
  printf -v "$1" '%s' "$__hu_s"
}

hook::json_str_object_to() {
  local __hu_dest="$1"
  shift
  local __hu_out="" __hu_ek __hu_ev
  while (($# >= 2)); do
    hook::json_escape_jq_to __hu_ek "$1"
    hook::json_escape_jq_to __hu_ev "$2"
    shift 2
    __hu_out+="${__hu_out:+,}\"$__hu_ek\":\"$__hu_ev\""
  done
  printf -v "$__hu_dest" '{%s}' "$__hu_out"
}

hook::read_file_path() {
  local -a __hu_chunks=()
  local __hu_chunk="" __hu_out=""
  while IFS= read -r -d '' __hu_chunk; do
    __hu_chunks+=("$__hu_chunk")
    __hu_chunk=""
  done
  __hu_chunks+=("$__hu_chunk")
  hook::read_file_path_to __hu_out "${__hu_chunks[@]}" || return 1
  printf '%s' "$__hu_out"
}

hook::read_file_path_to() {
  hook::read_file_path_uncached_to "$@"
}

hook::read_file_path_uncached_to() {
  local __hu_rf_dest="$1" __hu_rf_file="" __hu_rf_mode=2
  shift
  if (($# == 1)); then
    __hu_rf_mode=0
    hook::_fast_file_path_to __hu_rf_file "$1" || __hu_rf_mode=$?
  fi
  case "$__hu_rf_mode" in
  0) ;;          # proven: `__hu_rf_file` holds jq's answer
  1) return 1 ;; # proven absent
  *)
    __hu_rf_file=$(hook::_print_nul_joined "$@" | jq -r '(.tool_input.file_path // empty) | gsub("\r";"")' 2>/dev/null)
    ;;
  esac
  [[ -n "$__hu_rf_file" ]] || return 1
  [[ -f "$__hu_rf_file" ]] || return 1
  if [[ "${HOOK_READ_FILE_PATH_UNSCOPED:-0}" == 1 ]]; then
    printf -v "$__hu_rf_dest" '%s' "$__hu_rf_file"
    return 0
  fi
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    local __hu_rf_norm_file __hu_rf_norm_project __hu_rf_phys_file __hu_rf_phys_project
    local __hu_rf_file_resolved=0 __hu_rf_project_resolved=0
    hook::_temp_root_candidates
    hook::_physical_prime "$__hu_rf_file" "${CLAUDE_PROJECT_DIR}" ${_HOOK_TEMP_CANDS[@]+"${_HOOK_TEMP_CANDS[@]}"}
    hook::_physical_cached_to __hu_rf_phys_file "$__hu_rf_file" && __hu_rf_file_resolved=1
    hook::_phys_cache_forget "$__hu_rf_file"
    hook::_physical_cached_to __hu_rf_phys_project "${CLAUDE_PROJECT_DIR}" && __hu_rf_project_resolved=1
    hook::normalize_path_to __hu_rf_norm_file "$__hu_rf_phys_file"
    hook::normalize_path_to __hu_rf_norm_project "$__hu_rf_phys_project"
    __hu_rf_norm_project="${__hu_rf_norm_project%/}"
    if [[ "$__hu_rf_norm_file" != "$__hu_rf_norm_project" && "$__hu_rf_norm_file" != "$__hu_rf_norm_project"/* ]]; then
      return 1
    fi
    local __hu_rf_file_in_temp=0
    _HOOK_UTR_TARGET_PHYSICAL=$__hu_rf_file_resolved
    hook::under_temp_root "$__hu_rf_norm_file" && __hu_rf_file_in_temp=1
    _HOOK_UTR_TARGET_PHYSICAL=0
    if ((__hu_rf_file_in_temp)); then
      local __hu_rf_project_in_temp=0
      _HOOK_UTR_TARGET_PHYSICAL=$__hu_rf_project_resolved
      hook::under_temp_root "$__hu_rf_norm_project" && __hu_rf_project_in_temp=1
      _HOOK_UTR_TARGET_PHYSICAL=0
      ((__hu_rf_project_in_temp)) || return 1
    fi
  elif command -v git >/dev/null 2>&1; then
    local __hu_rf_file_physical __hu_rf_file_dir
    hook::physical_path_to __hu_rf_file_physical "$__hu_rf_file" || :
    if [[ -L "$__hu_rf_file" && "$__hu_rf_file_physical" == "$__hu_rf_file" ]]; then
      return 1
    fi
    hook::dirname_to __hu_rf_file_dir "$__hu_rf_file_physical"
    if ! hook::in_git_working_tree "$__hu_rf_file_dir"; then
      return 1
    fi
  else
    return 1
  fi
  printf -v "$__hu_rf_dest" '%s' "$__hu_rf_file"
}

hook::repo_root_to() {
  hook::repo_root_uncached_to "$@"
}

# shellcheck disable=SC2034  # public contract: advisory callers may read HOOK_REPO_ROOT_UNRESOLVED
hook::repo_root_uncached_to() {
  local __hu_rr_dest="$1"
  local __hu_rr_hint="${2:-.}"
  local __hu_rr_val
  HOOK_REPO_ROOT_UNRESOLVED=0
  __hu_rr_val=$(hook::git_untrusted -C "$__hu_rr_hint" rev-parse --show-toplevel 2>/dev/null) || __hu_rr_val=""
  __hu_rr_val="${__hu_rr_val//$'\r'/}"
  if [[ -n "$__hu_rr_val" ]]; then
    printf -v "$__hu_rr_dest" '%s' "$__hu_rr_val"
    return 0
  fi
  __hu_rr_val="${__hu_rr_hint%/.claude}"
  __hu_rr_val="${__hu_rr_val%\\.claude}"
  HOOK_REPO_ROOT_UNRESOLVED=1
  printf -v "$__hu_rr_dest" '%s' "$__hu_rr_val"
  return 1
}

hook::repo_root() {
  local __hu_rr
  hook::repo_root_to __hu_rr "${1:-.}"
  local __hu_rr_st=$?
  printf '%s' "$__hu_rr"
  return "$__hu_rr_st"
}

hook::walk_up_to() {
  local __hu_wu_dest="$1" __hu_wu_dir="$2" __hu_wu_ceiling="$3"
  local __hu_wu_pred="$4" __hu_wu_mode="${5:-first}"
  local __hu_wu_hit="" __hu_wu_parent __hu_wu_rc
  printf -v "$__hu_wu_dest" '%s' ""
  [[ -n "$__hu_wu_dir" && -n "$__hu_wu_ceiling" ]] || return 1
  while :; do
    "$__hu_wu_pred" "$__hu_wu_dir"
    __hu_wu_rc=$?
    if ((__hu_wu_rc == 0)); then
      __hu_wu_hit="$__hu_wu_dir"
      [[ "$__hu_wu_mode" == topmost ]] || break
    elif ((__hu_wu_rc != 1)); then
      break
    fi
    [[ "$__hu_wu_dir" == "$__hu_wu_ceiling" ]] && break
    __hu_wu_parent="${__hu_wu_dir%/*}"
    [[ -n "$__hu_wu_parent" ]] || __hu_wu_parent=/
    [[ "$__hu_wu_parent" == "$__hu_wu_dir" ]] && break
    __hu_wu_dir="$__hu_wu_parent"
  done
  printf -v "$__hu_wu_dest" '%s' "$__hu_wu_hit"
  [[ -n "$__hu_wu_hit" ]]
}

hook::_rstrip_slashes_to() {
  local __hu_rs_p="$2"
  while [[ "$__hu_rs_p" == */ && "$__hu_rs_p" != / ]]; do
    __hu_rs_p="${__hu_rs_p%/}"
  done
  printf -v "$1" '%s' "$__hu_rs_p"
}

hook::_strip_root_to() {
  local __hu_sr_pre="$3/"
  [[ "$2" == "$__hu_sr_pre"* ]] || { (($4)) && [[ "${2,,}" == "${__hu_sr_pre,,}"* ]]; } || return 1
  printf -v "$1" '%s' "${2:${#__hu_sr_pre}}"
}

# shellcheck disable=SC2034  # public contract: callers may read HOOK_REPO_RELATIVE_DEGRADED
hook::repo_relative_path_to() {
  local __hu_rp_dest="$1"
  local __hu_rp_file_n="$2" __hu_rp_root_n="$3" __hu_rp_rel=""
  local __hu_rp_file_c __hu_rp_root_c
  local __hu_rp_fold=0 __hu_rp_file_lm="" __hu_rp_root_lm=""
  HOOK_REPO_RELATIVE_DEGRADED=0
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    __hu_rp_fold=1
    __hu_rp_file_n="${__hu_rp_file_n//\\//}"
    __hu_rp_root_n="${__hu_rp_root_n//\\//}"
    ;;
  *) ;; # POSIX: keep the caller's spelling
  esac
  hook::_rstrip_slashes_to __hu_rp_root_n "$__hu_rp_root_n"
  hook::_rstrip_slashes_to __hu_rp_file_n "$__hu_rp_file_n"
  __hu_rp_file_c=$__hu_rp_file_n
  __hu_rp_root_c=$__hu_rp_root_n
  if [[ -n "$__hu_rp_root_n" ]]; then
    if ((__hu_rp_fold)); then
      __hu_rp_file_lm=$(cygpath -l -m -- "$__hu_rp_file_n" 2>/dev/null) || __hu_rp_file_lm=""
      __hu_rp_root_lm=$(cygpath -l -m -- "$__hu_rp_root_n" 2>/dev/null) || __hu_rp_root_lm=""
      if [[ -n "$__hu_rp_file_lm" && -n "$__hu_rp_root_lm" ]]; then
        hook::_rstrip_slashes_to __hu_rp_file_c "${__hu_rp_file_lm//\\//}"
        hook::_rstrip_slashes_to __hu_rp_root_c "${__hu_rp_root_lm//\\//}"
      fi
    fi
    hook::_strip_root_to __hu_rp_rel "$__hu_rp_file_c" "$__hu_rp_root_c" "$__hu_rp_fold" ||
      hook::_strip_root_to __hu_rp_rel "$__hu_rp_file_n" "$__hu_rp_root_n" "$__hu_rp_fold" ||
      __hu_rp_rel=$__hu_rp_file_c
  else
    __hu_rp_rel=$__hu_rp_file_n
  fi
  case "$__hu_rp_rel" in
  /* | [A-Za-z]:* | \\\\*)
    __hu_rp_rel="${__hu_rp_rel##*/}"
    __hu_rp_rel="${__hu_rp_rel##*\\}"
    HOOK_REPO_RELATIVE_DEGRADED=1
    ;;
  *) ;; # already repo-relative, nothing to redact
  esac
  printf -v "$__hu_rp_dest" '%s' "$__hu_rp_rel"
  ((HOOK_REPO_RELATIVE_DEGRADED == 0))
}

# read -N needs bash 4.1:
# https://tiswww.case.edu/php/chet/bash/NEWS
hook::read_supports_nchars() {
  ((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1)))
}

hook::json_complete() {
  [[ "${1: -4}" == *"}"* ]] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  printf '%s' "$1" | jq -e . >/dev/null 2>&1
}

readonly HOOK_STDIN_READ_TIMEOUT_MIN_MICROS=10

# A fractional read -t timeout needs bash 4.0:
# https://tiswww.case.edu/php/chet/bash/NEWS
hook::read_supports_fractional_timeout() {
  ((BASH_VERSINFO[0] >= 4))
}

hook::resolve_read_timeout_to() {
  local __hu_dest="$1"
  local __hu_t="${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}"
  local __hu_micros=0
  if [[ "$__hu_t" != "2" ]]; then
    if ! hook::_micros_to __hu_micros "$__hu_t" || ((__hu_micros < HOOK_STDIN_READ_TIMEOUT_MIN_MICROS)) ||
      { [[ "$__hu_t" == *.* ]] && ! hook::read_supports_fractional_timeout; }; then
      __hu_t=2
    fi
  fi
  printf -v "$__hu_dest" '%s' "$__hu_t"
}

hook::_micros_to() {
  [[ "$2" =~ ^([0-9]+)(\.([0-9]+))?$ ]] || return 1
  local __hu_mi_frac="${BASH_REMATCH[3]:-}000000"
  printf -v "$1" '%s' "$((10#${BASH_REMATCH[1]} * 1000000 + 10#${__hu_mi_frac:0:6}))"
}

HOOK_STDIN_READ_SLICES=4

hook::resolve_read_slice_to() {
  local __hu_t="$1" __hu_slice="" __hu_micros __hu_milli
  local __hu_slice_dest="$2" __hu_count_dest="$3"
  if hook::_micros_to __hu_micros "$__hu_t" && ((HOOK_STDIN_READ_SLICES > 0)); then
    __hu_milli=$(((__hu_micros / HOOK_STDIN_READ_SLICES + 500) / 1000))
    printf -v __hu_slice '%d.%03d' "$((__hu_milli / 1000))" "$((__hu_milli % 1000))"
  fi
  if [[ "$__hu_slice" =~ ^[0-9]+\.[0-9]+$ ]] && ! [[ "$__hu_slice" =~ ^0+\.0+$ ]] &&
    hook::read_supports_fractional_timeout; then
    printf -v "$__hu_slice_dest" '%s' "$__hu_slice"
    printf -v "$__hu_count_dest" '%s' "$HOOK_STDIN_READ_SLICES"
    return 0
  fi
  printf -v "$__hu_slice_dest" '%s' "$__hu_t"
  printf -v "$__hu_count_dest" '%s' "1"
}

hook::buffer_stdin_to() {
  local __hu_dest="$1"
  shift
  local __hu_input="" __hu_chunk="" __hu_read_rc=0 __hu_stalled=0
  local __hu_idle_slices=0 __hu_validated=0
  local __hu_read_timeout __hu_read_slice __hu_slice_count
  hook::resolve_read_timeout_to __hu_read_timeout
  hook::resolve_read_slice_to "$__hu_read_timeout" __hu_read_slice __hu_slice_count
  local -a __hu_read_opts=(-r -t "$__hu_read_slice")
  if hook::read_supports_nchars; then
    __hu_read_opts+=(-N 65536)
  else
    __hu_read_opts+=(-d '')
  fi
  while :; do
    __hu_chunk=""
    __hu_read_rc=0
    # shellcheck disable=SC2162 # -r is in __hu_read_opts; shellcheck cannot see through the array
    IFS= read "${__hu_read_opts[@]}" __hu_chunk || __hu_read_rc=$?
    __hu_input+="$__hu_chunk"
    [[ -n "$__hu_chunk" ]] && __hu_idle_slices=0
    if ((__hu_read_rc == 0)); then
      [[ -n "$__hu_chunk" ]] || break
      continue
    fi
    if ((__hu_read_rc > 128)); then
      if [[ -n "$__hu_chunk" ]]; then
        if hook::json_complete "${__hu_input//$'\r'/}"; then
          __hu_validated=1
          break
        fi
        continue
      fi
      if ((__hu_idle_slices == 0)) && hook::json_complete "${__hu_input//$'\r'/}"; then
        __hu_validated=1
        break
      fi
      ((__hu_idle_slices++))
      ((__hu_idle_slices >= __hu_slice_count)) || continue
      __hu_stalled=1
    fi
    break # EOF (rc 1), a full idle bound with no bytes, or a read error
  done
  __hu_input="${__hu_input//$'\r'/}"
  [[ -n "$__hu_input" ]] || return 1
  local __hu_jq_rc=0
  if (($#)); then
    local __hu_fields_rc=0
    hook::jq_fields "$__hu_input" "$@" || __hu_fields_rc=$?
    if ((__hu_fields_rc == 2)); then
      __hu_jq_rc=2
    fi
  elif ((__hu_validated == 0)) && command -v jq >/dev/null 2>&1 &&
    ! hook::_json_object_proven "$__hu_input"; then
    printf '%s' "$__hu_input" | jq -e . >/dev/null 2>&1 || __hu_jq_rc=$?
  fi
  if ((__hu_jq_rc != 0 && __hu_jq_rc != 127)); then
    if ((__hu_stalled)); then
      echo "BLOCKED: hook stdin timed out before a complete JSON payload arrived." >&2
      return 2
    fi
    [[ -n "${__hu_input//[[:space:]]/}" ]] || return 1
    local __hu_jq_err=""
    __hu_jq_err=$(printf '%s' "$__hu_input" | jq -e . 2>&1 >/dev/null) || true
    if [[ "$__hu_jq_err" == *Unfinished* ]]; then
      echo "hook stdin was cut short: ${#__hu_input} characters of a JSON payload arrived, then the pipe closed before the document was complete (a transport fault, not a property of the tool call)." >&2
      return 3
    fi
    echo "BLOCKED: hook stdin is not valid JSON." >&2
    return 2
  fi
  printf -v "$__hu_dest" '%s' "$__hu_input"
}

hook::buffer_stdin() {
  local __hu_buf
  hook::buffer_stdin_to __hu_buf || return $?
  printf '%s' "$__hu_buf"
}

hook::jq_field() {
  local field
  field=$(printf '%s' "$1" | jq -r "(${2} // empty)"' | gsub("\r";"")' 2>/dev/null)
  [[ -n "$field" ]] || return 1
  printf '%s' "$field"
}

# shellcheck disable=SC2034  # result globals are consumed by the sourcing hook, not this file
hook::jq_fields() {
  hook::jq_fields_uncached "$@"
}

# shellcheck disable=SC2034  # result globals are consumed by the sourcing hook, not this file
hook::jq_fields_uncached() {
  local input="$1"
  shift
  HOOK_JQ_FIELDS=()
  HOOK_JQ_FIELDS_NUL=0
  (($#)) || return 1
  command -v jq >/dev/null 2>&1 || return 1
  if hook::_fast_fields_supported && hook::_fast_fields "$input" "$@"; then
    return 0
  fi
  HOOK_JQ_FIELDS=()
  HOOK_JQ_FIELDS_NUL=0
  local prog="" filter
  for filter in "$@"; do
    [[ -n "$prog" ]] && prog+=","
    prog+="((${filter}) // \"\" | tostring)"
  done
  prog="[$prog]"
  prog+=' | ((if (map(explode | index(0) != null) | any) then "1" else "0" end),'
  prog+=' (.[] | split("\u0000") | join("")))'
  prog+=" | (., \"\\u0000\")"
  local -a values=()
  local v clean
  # read -d '', not mapfile -d, which needs bash 4.4:
  # https://tiswww.case.edu/php/chet/bash/NEWS
  while IFS= read -r -d '' v; do
    clean="${v//$'\r'/}"
    values+=("$clean")
  done < <(printf '%s' "$input" | jq -j "$prog" 2>/dev/null)
  ((${#values[@]} == $# + 1)) || return 2
  HOOK_JQ_FIELDS_NUL="${values[0]}"
  HOOK_JQ_FIELDS=("${values[@]:1}")
}

hook::raw_notebook_path() {
  [[ "$1" =~ \"notebook_path\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]] || return 1
  [[ -n "${BASH_REMATCH[1]}" ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

hook::path_matches() {
  local __hu_pm_path="$1" __hu_pm_norm __hu_pm_glob
  shift
  hook::normalize_path_to __hu_pm_norm "$__hu_pm_path"
  for __hu_pm_glob in "$@"; do
    # shellcheck disable=SC2254  # the glob is the pattern; quoting would match it literally
    case "$__hu_pm_path" in
    $__hu_pm_glob) return 0 ;;
    *) ;; # try the normalized spelling below, then the next glob
    esac
    # shellcheck disable=SC2254  # same, on the normalized spelling
    case "$__hu_pm_norm" in
    $__hu_pm_glob) return 0 ;;
    *) ;; # no match for this glob; try the next
    esac
  done
  return 1
}

hook::data_json_to() {
  local __hu_dj_dest="$1" __hu_dj_tool="$2" __hu_dj_file="$3" __hu_dj_changed="$4"
  shift 4
  local __hu_dj_stdin="{" __hu_dj_sep=""
  # shellcheck disable=SC2016  # jq program text: $tool and $file are jq's own variables
  local __hu_dj_prog='{tool:$tool,file:$file}'
  local __hu_dj_fallback='{"tool":"","file":""'
  local -a __hu_dj_args=(--arg tool "$__hu_dj_tool" --arg file "$__hu_dj_file"
    --arg changed "$__hu_dj_changed")
  local __hu_dj_key __hu_dj_kind __hu_dj_val
  while (($# >= 3)); do
    __hu_dj_key="$1"
    __hu_dj_kind="$2"
    __hu_dj_val="$3"
    shift 3
    case "$__hu_dj_kind" in
    array)
      __hu_dj_stdin+="${__hu_dj_sep}\"${__hu_dj_key}\":${__hu_dj_val:-[]}"
      __hu_dj_sep=","
      __hu_dj_prog+=" + {${__hu_dj_key}: .${__hu_dj_key}}"
      __hu_dj_fallback+=",\"${__hu_dj_key}\":[]"
      ;;
    *)
      __hu_dj_args+=(--arg "$__hu_dj_key" "$__hu_dj_val")
      __hu_dj_prog+=" + {${__hu_dj_key}: \$${__hu_dj_key}}"
      __hu_dj_fallback+=",\"${__hu_dj_key}\":\"\""
      ;;
    esac
  done
  __hu_dj_stdin+="}"
  __hu_dj_fallback+="}"
  # shellcheck disable=SC2016  # jq program text: $changed is jq's own variable
  __hu_dj_prog+=' + (if $changed == "" then {} else {changed: ($changed == "true")} end)'
  local __hu_dj_out=""
  __hu_dj_out=$(printf '%s' "$__hu_dj_stdin" |
    jq -c "${__hu_dj_args[@]}" "$__hu_dj_prog" 2>/dev/null) || __hu_dj_out=""
  __hu_dj_out="${__hu_dj_out//$'\r'/}"
  [[ -n "$__hu_dj_out" ]] || __hu_dj_out="$__hu_dj_fallback"
  printf -v "$__hu_dj_dest" '%s' "$__hu_dj_out"
}

# shellcheck disable=SC2034  # the caller's contract: every name above is read by the hook, not here
hook::begin() {
  local __hu_bg_relative=0 __hu_bg_unscoped=0 __hu_bg_notebook=0
  local __hu_bg_root_fn="" __hu_bg_prejq_fn=""
  while (($#)); do
    case "$1" in
    --relative) __hu_bg_relative=1 ;;
    --no-membership) __hu_bg_unscoped=1 ;;
    --notebook) __hu_bg_notebook=1 ;;
    --repo-root)
      __hu_bg_root_fn="$2"
      shift
      ;;
    --pre-jq)
      __hu_bg_prejq_fn="$2"
      shift
      ;;
    *) break ;;
    esac
    shift
  done
  local __hu_bg_plugin="$1" __hu_bg_event="$2"
  shift 2
  HOOK_PLUGIN="$__hu_bg_plugin"
  HOOK_EVENT="$__hu_bg_event"

  # EPOCHREALTIME is new in bash 5.0, so older bash leaves it unset under set -u:
  # https://cgit.git.savannah.gnu.org/cgit/bash.git/plain/NEWS
  start=${EPOCHREALTIME:-}

  hook::buffer_stdin_to INPUT || exit 0

  RAW_FILE=""
  hook::raw_file_path_to RAW_FILE "$INPUT" || :
  if [[ -z "$RAW_FILE" ]] && ((__hu_bg_notebook)); then
    RAW_FILE=$(hook::raw_notebook_path "$INPUT") || RAW_FILE=""
  fi
  [[ -n "$RAW_FILE" ]] || exit 0
  if (($#)); then
    hook::path_matches "${RAW_FILE//\\\\/\\}" "$@" || exit 0
  fi

  [[ -n "$__hu_bg_prejq_fn" ]] && "$__hu_bg_prejq_fn" "$RAW_FILE"

  hook::require jq "$__hu_bg_event" "$__hu_bg_plugin" "$INPUT"

  if ((__hu_bg_notebook)) && hook::raw_notebook_path "$INPUT" >/dev/null; then
    local __hu_bg_normalized
    __hu_bg_normalized=$(printf '%s' "$INPUT" | jq -c '
      if ((.tool_input.file_path // "") == "") and ((.tool_input.notebook_path // "") != "")
      then .tool_input.file_path = .tool_input.notebook_path
      else . end' 2>/dev/null) &&
      [[ -n "$__hu_bg_normalized" ]] && INPUT="$__hu_bg_normalized"
  fi

  local HOOK_READ_FILE_PATH_UNSCOPED="$__hu_bg_unscoped"
  FILE=""
  hook::read_file_path_to FILE "$INPUT" || exit 0
  if (($#)); then
    hook::path_matches "$FILE" "$@" || exit 0
  fi

  FILE_BASE="${FILE##*/}"
  FILE_BASE="${FILE_BASE##*\\}"
  FILE_DIR="${FILE%/*}"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32) FILE_DIR="${FILE%[/\\]*}" ;;
  *) ;; # POSIX: keep the slash-only split
  esac
  [[ "$FILE_DIR" == "$FILE" ]] && FILE_DIR=.
  [[ -n "$FILE_DIR" ]] || FILE_DIR=/
  [[ "$FILE_DIR" == [A-Za-z]: ]] && FILE_DIR+="${FILE:2:1}"

  REPO_ROOT=""
  if [[ -n "$__hu_bg_root_fn" ]]; then
    "$__hu_bg_root_fn" REPO_ROOT "$FILE_DIR"
  else
    hook::repo_root_to REPO_ROOT "$FILE_DIR"
  fi

  TOOL=""
  FILE_REL="$FILE"
  FILE_REL_DEGRADED=0
  local __hu_bg_telemetry=0
  hook::telemetry_enabled && __hu_bg_telemetry=1
  if ((__hu_bg_relative || __hu_bg_telemetry)); then
    FILE_REL=""
    hook::repo_relative_path_to FILE_REL "$FILE" "$REPO_ROOT" || FILE_REL_DEGRADED=1
  fi
  if ((__hu_bg_telemetry)); then
    hook::jq_fields "$INPUT" '.tool_name' && TOOL="${HOOK_JQ_FIELDS[0]}"
  fi
  return 0
}

hook::finish() {
  local __hu_fi_ctx="" __hu_fi_msg="" __hu_fi_disclose="" __hu_fi_changed=""
  local __hu_fi_changed_set=0 __hu_fi_id="${HOOK_PLUGIN:-}"
  while (($#)); do
    case "$1" in
    --context)
      __hu_fi_ctx="$2"
      shift
      ;;
    --message)
      __hu_fi_msg="$2"
      shift
      ;;
    --disclose)
      __hu_fi_disclose="$2"
      shift
      ;;
    --changed)
      __hu_fi_changed="$2"
      __hu_fi_changed_set=1
      shift
      ;;
    --id)
      __hu_fi_id="$2"
      shift
      ;;
    *) break ;;
    esac
    shift
  done
  local __hu_fi_status="$1"
  shift

  local __hu_fi_sysmsg=""
  if declare -F hook::rewrite_take_disclosure >/dev/null 2>&1; then
    hook::rewrite_take_disclosure "" "$__hu_fi_disclose"
    # shellcheck disable=SC2154  # the take's two outputs, assigned in rewrite-guard.sh
    __hu_fi_sysmsg="$HOOK_REWRITE_MESSAGE"
    ((__hu_fi_changed_set)) || __hu_fi_changed="${HOOK_REWRITE_CHANGED:-}"
  fi
  if [[ -n "$__hu_fi_msg" ]]; then
    [[ -n "$__hu_fi_sysmsg" ]] && __hu_fi_sysmsg+=$'\n'
    __hu_fi_sysmsg+="$__hu_fi_msg"
  fi

  if [[ -n "${start:-}" ]] && hook::telemetry_enabled; then
    local __hu_fi_data=""
    hook::data_json_to __hu_fi_data "${TOOL:-}" "${FILE_REL:-}" "$__hu_fi_changed" "$@"
    hook::emit_telemetry "$__hu_fi_id" "${HOOK_EVENT:-}" "$__hu_fi_status" \
      "$start" "$__hu_fi_data" "${REPO_ROOT:-}"
  fi

  hook::emit_channels "${HOOK_EVENT:-}" "$__hu_fi_ctx" "$__hu_fi_sysmsg"
  exit 0
}

hook::extract_bash_subject() {
  local __hu_subject
  hook::extract_bash_subject_to __hu_subject "$1" "${2:-}"
  printf '%s' "$__hu_subject"
}

hook::extract_bash_subject_to() {
  local __hu_dest="$1" tool="$2" cmd="${3:-}"
  if [[ "$tool" != "Bash" ]]; then
    printf -v "$__hu_dest" '%s' "$tool"
    return 0
  fi
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  local first_token="${cmd%%[[:space:]]*}"
  while [[ "$first_token" == "sudo" || "$first_token" == *=* ]] &&
    [[ -n "$cmd" && "$cmd" == *[[:space:]]* ]]; do
    [[ "$first_token" == *[\"\']* ]] && break
    cmd="${cmd#*[[:space:]]}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    first_token="${cmd%%[[:space:]]*}"
  done
  if [[ "$first_token" != *[\"\']* && ! "$first_token" =~ ^[a-zA-Z_][a-zA-Z0-9_]*(\[.*\])?\+?= ]]; then
    first_token="${first_token##*/}"
    if [[ -n "$first_token" ]]; then
      printf -v "$__hu_dest" 'Bash:%s' "$first_token"
      return 0
    fi
  fi
  printf -v "$__hu_dest" '%s' "$tool"
}

hook::append_jsonl() {
  local file="$1" line="$2"
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 2 9 || exit 0
      printf '%s\n' "$line" >>"$file"
    ) 9>"${file}.lock" 2>/dev/null
  else
    printf '%s\n' "$line" >>"$file" 2>/dev/null
  fi
}

_HOOK_CTX_BUFFER=""

hook::ctx_reset() {
  _HOOK_CTX_BUFFER=""
}

hook::ctx_append() {
  _HOOK_CTX_BUFFER+="$1"$'\n'
}

hook::ctx_take_to() {
  local __hu_ct_trimmed="${_HOOK_CTX_BUFFER%"${_HOOK_CTX_BUFFER##*[![:space:]]}"}"
  __hu_ct_trimmed="${__hu_ct_trimmed#"${__hu_ct_trimmed%%[![:space:]]*}"}"
  hook::ctx_reset
  printf -v "$1" '%s' "$__hu_ct_trimmed"
}

hook::ctx_flush() {
  local __hu_cf_trimmed=""
  hook::ctx_take_to __hu_cf_trimmed
  hook::emit_channels "$1" "$__hu_cf_trimmed" ""
}

hook::telemetry_enabled() {
  [[ -n "${HOOK_TELEMETRY_SINK:-}" ]]
}

hook::session_telemetry_sink_to() {
  local __hu_hos_data="${CLAUDE_PLUGIN_DATA:-}" __hu_hos_cfg __hu_hos_root __hu_hos_c __hu_hos_best=""
  local -a __hu_hos_roots=()
  __hu_hos_data="${__hu_hos_data//\\//}"
  __hu_hos_data="${__hu_hos_data%/}"
  [[ -n "$__hu_hos_data" ]] && __hu_hos_roots+=("${__hu_hos_data%/*}")
  __hu_hos_cfg="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
  __hu_hos_cfg="${__hu_hos_cfg//\\//}"
  # Plugin data directories sit at <config dir>/plugins/data/<id>:
  # https://code.claude.com/docs/en/plugins-reference#environment-variables
  __hu_hos_roots+=("${__hu_hos_cfg%/}/plugins/data")
  for __hu_hos_root in "${__hu_hos_roots[@]}"; do
    for __hu_hos_c in "$__hu_hos_root"/session-telemetry-*/hook-telemetry-sink.sh; do
      [[ -x "$__hu_hos_c" ]] || continue
      [[ -z "$__hu_hos_best" || "$__hu_hos_c" -nt "$__hu_hos_best" ]] && __hu_hos_best="$__hu_hos_c"
    done
  done
  [[ -n "$__hu_hos_best" ]] || return 1
  printf -v "$1" '%s' "$__hu_hos_best"
}

hook::emit_telemetry() {
  [[ -n "${HOOK_TELEMETRY_SINK:-}" ]] || return 0

  local hook_id="$1"
  local hook_event="$2"
  local status="$3"
  local start_epoch="$4"
  local data_json="$5"
  local repo_root="${6:-}"

  local now=${EPOCHREALTIME:-}
  [[ -n "$start_epoch" && -n "$now" ]] || return 0
  local s_s="${start_epoch%[.,]*}" s_f="${start_epoch#*[.,]}"
  local e_s="${now%[.,]*}" e_f="${now#*[.,]}"
  local duration_ms=$(((e_s * 1000000 + 10#$e_f - s_s * 1000000 - 10#$s_f) / 1000))

  local timestamp=""
  # printf %(fmt)T needs bash 4.2; older bash falls back to date:
  # https://tiswww.case.edu/php/chet/bash/NEWS
  TZ=UTC printf -v timestamp '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || timestamp=""
  [[ -n "$timestamp" ]] || timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || timestamp=""

  local corr="" corr_key corr_payload="${HOOK_TELEMETRY_PAYLOAD-${INPUT-}}"
  if [[ -n "$corr_payload" ]]; then
    local corr_cut=':[[:space:]]*[[{]'
    local corr_t=""
    if ((${#corr_payload} <= 65536)); then
      corr_t=$corr_payload
      if [[ $corr_t == *\\* ]]; then
        corr_t=${corr_t//"\\\\"/@@}
        corr_t=${corr_t//"\\\""/@@}
      fi
    fi
    local corr_parts corr_i corr_n corr_depth=0 corr_root="" corr_seg
    local corr_o corr_c
    local corr_glob=0
    [[ $- == *f* ]] || corr_glob=1
    set -f
    local IFS='"'
    # shellcheck disable=SC2206 # splitting on IFS='"' is the whole point
    corr_parts=($corr_t)
    ((corr_glob)) && set +f
    IFS=$' \t\n'
    corr_n=${#corr_parts[@]}
    if ((corr_n % 2 == 1 && corr_n > 1)); then
      for ((corr_i = 0; corr_i < corr_n; corr_i++)); do
        if ((corr_i % 2 == 0)); then
          corr_seg=${corr_parts[corr_i]}
          corr_root+=$corr_seg
          corr_o=${corr_seg//[\{\[]/}
          corr_c=${corr_seg//[\}\]]/}
          corr_depth=$((corr_depth + ${#corr_c} - ${#corr_o}))
        elif ((corr_depth == 1)); then
          corr_root+='"'${corr_parts[corr_i]}'"'
        fi
      done
    else
      corr_root=$corr_payload
      if [[ "$corr_root" =~ $corr_cut ]]; then
        corr_root=${corr_root%%"${BASH_REMATCH[0]}"*}
      fi
    fi
    for corr_key in session_id prompt_id tool_use_id agent_id; do
      if [[ "$corr_root" =~ \"$corr_key\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]]; then
        corr+='"'"$corr_key"'":"'"${BASH_REMATCH[1]}"'",'
      fi
    done
  fi

  local envelope="" data="" data_trim="$data_json"
  while [[ "$data_trim" == *[$' \t\r\n'] ]]; do
    data_trim="${data_trim%?}"
  done
  if [[ "$data_trim" == \{*\} ]] && hook::json_compact_to data "$data_trim"; then
    local e_timestamp e_hook e_event e_status
    hook::json_escape_jq_to e_timestamp "$timestamp"
    hook::json_escape_jq_to e_hook "$hook_id"
    hook::json_escape_jq_to e_event "$hook_event"
    hook::json_escape_jq_to e_status "$status"
    envelope='{"schema_version":"1.1","timestamp":"'"$e_timestamp"'","hook":"'"$e_hook"'","hook_event":"'"$e_event"'","status":"'"$e_status"'","duration_ms":'"$duration_ms"','"$corr"'"data":'"$data"'}'
  else
    command -v jq >/dev/null 2>&1 || return 0
    local data_file envelope_rc=0
    # The data goes through a file: a Windows command line holds at most 32,767 characters:
    # https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
    data_file=$(mktemp) || return 0
    printf '%s' "$data_json" >"$data_file" && envelope=$(jq -nc \
      --arg schema_version "1.1" \
      --arg timestamp "$timestamp" \
      --arg hook "$hook_id" \
      --arg hook_event "$hook_event" \
      --arg status "$status" \
      --argjson duration_ms "$duration_ms" \
      --argjson corr "{${corr%,}}" \
      --slurpfile data "$data_file" \
      '{schema_version:$schema_version,timestamp:$timestamp,hook:$hook,hook_event:$hook_event,status:$status,duration_ms:$duration_ms} + $corr + {data:($data[0] // {})}' \
      2>/dev/null) || envelope_rc=1
    rm -f "$data_file"
    ((envelope_rc == 0)) || return 0
  fi

  local sink="$HOOK_TELEMETRY_SINK"
  case "$sink" in
  @session-telemetry | @harness-ops)
    hook::session_telemetry_sink_to sink || return 0
    ;;
  @*) return 0 ;;
  /* | [A-Za-z]:[/\\]*) ;;
  *)
    local root="${repo_root:-${CLAUDE_PROJECT_DIR:-}}"
    [[ -n "$root" ]] || return 0
    sink="${root%/}/$sink"
    ;;
  esac

  printf '%s\n' "$envelope" | ("$sink" >/dev/null 2>&1) &
}

hook::ansi_c_decode_to() {
  local __hu_acd_b="${2//%/%%}"
  # shellcheck disable=SC2059  # the body IS the format — that is how ANSI-C escapes decode; %-escaped above so it cannot inject a specifier
  printf -v "$1" -- "$__hu_acd_b" 2>/dev/null || printf -v "$1" '%s' ""
}

# shellcheck disable=SC2034  # result global is consumed by hook::git_resolve_index
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
hook::env_s_split() {
  local s="$1" i c n=${#1} word="" have=0
  HOOK_ENV_S_WORDS=()
  for ((i = 0; i < n; i++)); do
    c="${s:i:1}"
    case "$c" in
    "'")
      ((i++))
      while ((i < n)) && [[ "${s:i:1}" != "'" ]]; do
        word+="${s:i:1}"
        ((i++))
      done
      have=1
      ;;
    '"')
      ((i++))
      while ((i < n)) && [[ "${s:i:1}" != '"' ]]; do
        [[ "${s:i:1}" == '\' ]] && ((i + 1 < n)) && ((i++))
        word+="${s:i:1}"
        ((i++))
      done
      have=1
      ;;
    '\')
      if ((i + 1 < n)); then
        word+="${s:i+1:1}"
        ((i++))
      fi
      have=1
      ;;
    ' ' | $'\t')
      if ((have)); then
        HOOK_ENV_S_WORDS+=("$word")
        word=""
        have=0
      fi
      ;;
    *)
      word+="$c"
      have=1
      ;;
    esac
  done
  ((have)) && HOOK_ENV_S_WORDS+=("$word")
}

# shellcheck disable=SC2034  # result global is consumed by the sourcing guard
hook::shell_c_operand() {
  local -a w=("$@")
  local n=${#w[@]} i=0 b t has_c=0
  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done
  ((i < n)) || return 1
  b="${w[i]##*/}"
  b="${b##*\\}"
  t="${b,,}"
  if [[ "${t%.exe}" == wsl ]]; then
    hook::wsl_operand "${w[@]:i+1}"
    return
  fi
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    b="${b,,}"
    b="${b%.exe}"
    ;;
  *) ;;
  esac
  case "$b" in
  bash | sh | zsh | dash | ksh | mksh) ;;
  *) return 1 ;;
  esac
  ((i++))
  while ((i < n)); do
    t="${w[i]}"
    case "$t" in
    --)
      ((i++))
      break
      ;;
    -o | +o | -O | +O | --rcfile | --init-file) ((i += 2)) ;;
    -*)
      [[ "$t" =~ ^-[A-Za-z]+$ && "$t" == *c* ]] && has_c=1
      ((i++))
      ;;
    *) break ;;
    esac
  done
  ((has_c && i < n)) || return 1
  HOOK_SHELL_C_OPERAND="${w[i]}"
  return 0
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
# shellcheck disable=SC2034  # result global is consumed by the sourcing guard
hook::wsl_operand() {
  local -a w=("$@")
  local n=${#w[@]} i=0 exec_mode=0 out="" wd enc bs nb k ch
  local guid='^\{?[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}?$'
  ((i < n)) && [[ "${w[i]}" =~ $guid ]] && ((++i))
  ((i < n)) && [[ "${w[i]}" == "~" ]] && ((++i))
  while ((i < n)); do
    case "${w[i]}" in
    --)
      ((++i))
      break
      ;;
    -e | --exec)
      exec_mode=1
      ((++i))
      break
      ;;
    --shell-type)
      [[ "${w[i + 1]-}" == none ]] && exec_mode=1
      ((i += 2))
      ;;
    -d | --distribution | --distribution-id | -u | --user | --cd | --parent-console) ((i += 2)) ;;
    -*) ((++i)) ;;
    *) break ;;
    esac
  done
  ((i < n)) || return 1
  if ((exec_mode)); then
    local safe='^[][A-Za-z0-9_./:=+,@%~*?^-]+$'
    for wd in "${w[@]:i}"; do
      if [[ "$wd" =~ $safe ]]; then
        out+="$wd "
      else
        out+="'${wd//\'/\'\\\'\'}' "
      fi
    done
  else
    for wd in "${w[@]:i}"; do
      if [[ -n "$wd" && "$wd" != *[[:space:]\"]* ]]; then
        out+="$wd "
        continue
      fi
      # MSVCRT: backslashes are literal unless they immediately precede a double quote:
      # https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments
      enc='"'
      nb=0
      for ((k = 0; k < ${#wd}; k++)); do
        ch="${wd:k:1}"
        if [[ "$ch" == '\' ]]; then
          ((++nb))
          continue
        fi
        [[ "$ch" == '"' ]] && nb=$((2 * nb + 1))
        printf -v bs '%*s' "$nb" ''
        enc+="${bs// /\\}$ch"
        nb=0
      done
      printf -v bs '%*s' "$((2 * nb))" ''
      out+="$enc${bs// /\\}\" "
    done
  fi
  HOOK_SHELL_C_OPERAND="${out% }"
  return 0
}

hook::git_is_bin() {
  local b="${1##*/}"
  b="${b##*\\}"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    local lc="${b,,}"
    lc="${lc%.exe}"
    [[ "$lc" == "git" ]]
    ;;
  *) [[ "$b" == "git" ]] ;;
  esac
}

hook::wrapper_chdir_record() {
  # shellcheck disable=SC2178  # nameref to the caller's integer slot, not a string
  local -n slot="$1"
  local dir="$2"
  [[ -n "$dir" ]] || return 0
  if ((slot < 0)); then
    HOOK_GIT_RESOLVED_WRAPPER_DIRS+=("$dir")
    slot=$((${#HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]} - 1))
  else
    HOOK_GIT_RESOLVED_WRAPPER_DIRS[slot]="$dir"
  fi
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
# shellcheck disable=SC2034  # result globals are consumed by the sourcing guard, not this file
hook::git_resolve_index() {
  HOOK_GIT_RESOLVED_WORDS=("$@")
  HOOK_GIT_RESOLVED_GI=-1
  HOOK_GIT_RESOLVED_WRAPPER_DIRS=()
  # shellcheck disable=SC2178  # nameref to the array result global, not a string assignment
  local -n w=HOOK_GIT_RESOLVED_WORDS
  local n=${#w[@]} i=0 tok

  while ((i < n)); do
    tok="${w[i]}"
    if [[ "$tok" == *=* ]]; then
      ((i++))
      continue
    fi

    case "${tok##*/}" in
    env)
      ((i++))
      local env_past_optmark=0 env_ci=-1 etok
      while ((i < n)); do
        if ((env_past_optmark == 0)) && [[ "${w[i]}" == -* ]]; then
          etok="${w[i]}"
          while [[ "$etok" =~ ^-[i0v](.+)$ ]]; do etok="-${BASH_REMATCH[1]}"; done
          case "$etok" in
          --)
            ((i++))
            env_past_optmark=1
            ;;
          -S* | --split-string | --split-string=*)
            local sval skip=1
            if [[ "$etok" == -S || "$etok" == --split-string ]]; then
              sval="${w[i + 1]-}"
              skip=2
            else
              sval="${etok#-S}"
              sval="${sval#--split-string=}"
            fi
            hook::env_s_split "$sval"
            w=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} "${w[@]:i+skip}")
            n=${#w[@]}
            i=0
            continue
            ;;
          -C | --chdir)
            ((i + 1 < n)) && hook::wrapper_chdir_record env_ci "${w[i + 1]}"
            ((i += 2))
            ;;
          --chdir=*)
            hook::wrapper_chdir_record env_ci "${etok#--chdir=}"
            ((i++))
            ;;
          -C*)
            hook::wrapper_chdir_record env_ci "${etok#-C}"
            ((i++))
            ;;
          -u | --unset) ((i += 2)) ;;
          *) ((i++)) ;;
          esac
        elif [[ "${w[i]}" == *=* ]]; then
          env_past_optmark=1
          ((i++))
        else
          break
        fi
      done
      continue
      ;;
    nice | nohup)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -n | --adjustment) ((i += 2)) ;;
        *) ((i++)) ;;
        esac
      done
      ((i < n)) && [[ "${w[i]}" =~ ^-?[0-9]+$ ]] && ((i++))
      continue
      ;;
    sudo)
      ((i++))
      local sudo_ci=-1 stok
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        stok="${w[i]}"
        while [[ "$stok" =~ ^-[ABbeEHKklnPsSvV](.+)$ ]]; do stok="-${BASH_REMATCH[1]}"; done
        case "$stok" in
        -D | --chdir)
          ((i + 1 < n)) && hook::wrapper_chdir_record sudo_ci "${w[i + 1]}"
          ((i += 2))
          ;;
        --chdir=*)
          hook::wrapper_chdir_record sudo_ci "${stok#--chdir=}"
          ((i++))
          ;;
        -D*)
          hook::wrapper_chdir_record sudo_ci "${stok#-D}"
          ((i++))
          ;;
        -u | -g | -h | -p | -C | -R | -T | --user | --group) ((i += 2)) ;;
        *) ((i++)) ;;
        esac
      done
      continue
      ;;
    timeout)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -s | --signal | -k | --kill-after) ((i += 2)) ;;
        *) ((i++)) ;;
        esac
      done
      ((i < n)) && [[ "${w[i]}" =~ ^[0-9]+([.][0-9]+)?(s|m|h|d)?$ ]] && ((i++))
      continue
      ;;
    command | exec | builtin | eval | !)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* && "${w[i]}" != "--" ]]; do
        [[ "${tok##*/}" == command && "${w[i]}" == -*[vV]* ]] && return 1
        [[ "${w[i]}" == "-a" ]] && ((i++))
        ((i++))
      done
      ((i < n)) && [[ "${w[i]}" == "--" ]] && ((i++))
      continue
      ;;
    time)
      ((i++))
      ((i < n)) && [[ "${w[i]}" == "-p" ]] && ((i++))
      continue
      ;;
    if | then | elif | else | while | until | for | do | case | select | coproc | '{' | '}')
      ((i++))
      continue
      ;;
    *)
      if hook::git_is_bin "$tok"; then
        HOOK_GIT_RESOLVED_GI=$i
        return 0
      fi
      return 1
      ;;
    esac
  done
  return 1
}

# Call as: hook::git_resolve_subcommand <git-index> <argv words...>
# shellcheck disable=SC2034  # result globals are consumed by the sourcing guard, not this file
hook::git_resolve_subcommand() {
  local gi="$1"
  shift
  local -a w=("$@")
  local nseg=${#w[@]} j gw kind
  HOOK_GIT_SUB=""
  HOOK_GIT_SUB_IDX=-1
  HOOK_GIT_CONFIG_VALUES=()
  HOOK_GIT_CONFIG_VALUE_KINDS=()

  j=$((gi + 1))
  while ((j < nseg)); do
    gw="${w[j]}"
    case "$gw" in
    -c | --config | --config-env | --config=* | --config-env=*)
      kind="inline"
      [[ "$gw" == --config-env* ]] && kind="env"
      if [[ "$gw" == *=* ]]; then
        HOOK_GIT_CONFIG_VALUES+=("${gw#*=}")
      elif ((++j < nseg)); then
        HOOK_GIT_CONFIG_VALUES+=("${w[j]}")
      else
        break
      fi
      HOOK_GIT_CONFIG_VALUE_KINDS+=("$kind")
      ((j++))
      ;;
    -C | --git-dir | --work-tree | --namespace | --super-prefix | --attr-source | --exec-path)
      ((j += 2))
      ;;
    -*)
      ((j++))
      ;;
    *)
      HOOK_GIT_SUB="$gw"
      HOOK_GIT_SUB_IDX=$j
      return 0
      ;;
    esac
  done
  return 1
}

# shellcheck disable=SC2034  # HOOK_GIT_ALIAS_EXPS is consumed by the sourcing guard
hook::git_alias_expansion() {
  local sub="$1" i cv key kind
  local plain_exp="" plain_kind="" cmd_exp="" cmd_kind=""
  HOOK_GIT_ALIAS_EXPS=()
  # git config variable names are case-insensitive, so the key match folds case:
  # https://git-scm.com/docs/git-config#_syntax
  for i in "${!HOOK_GIT_CONFIG_VALUES[@]}"; do
    cv="${HOOK_GIT_CONFIG_VALUES[i]}"
    key="${cv%%=*}"
    kind="${HOOK_GIT_CONFIG_VALUE_KINDS[i]:-inline}"
    if [[ "${key,,}" == "alias.${sub,,}" ]]; then
      plain_exp="${cv#*=}"
      plain_kind="$kind"
    elif [[ "${key,,}" == "alias.${sub,,}.command" ]]; then
      cmd_exp="${cv#*=}"
      cmd_kind="$kind"
    fi
  done
  [[ "$plain_kind" == "env" || "$cmd_kind" == "env" ]] && return 2
  [[ -n "$plain_kind" ]] && HOOK_GIT_ALIAS_EXPS+=("$plain_exp")
  [[ -n "$cmd_kind" ]] && HOOK_GIT_ALIAS_EXPS+=("$cmd_exp")
  ((${#HOOK_GIT_ALIAS_EXPS[@]})) && return 0
  return 1
}

# shellcheck disable=SC2034  # result globals are consumed by the sourcing guard, not this file
hook::git_invocation() {
  HOOK_GITINV_GI=-1
  HOOK_GITINV_WORDS=()
  HOOK_GITINV_WRAPPER_DIRS=()
  HOOK_GITINV_SUB=""
  HOOK_GITINV_SUB_IDX=-1
  HOOK_GITINV_CONFIG_VALUES=()
  HOOK_GITINV_CONFIG_KINDS=()
  HOOK_GITINV_ALIAS_EXPS=()
  HOOK_GITINV_ALIAS_TERM="none"

  hook::git_resolve_index "$@" || return 1
  HOOK_GITINV_GI=$HOOK_GIT_RESOLVED_GI
  HOOK_GITINV_WORDS=(${HOOK_GIT_RESOLVED_WORDS[@]+"${HOOK_GIT_RESOLVED_WORDS[@]}"})
  HOOK_GITINV_WRAPPER_DIRS=(${HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]+"${HOOK_GIT_RESOLVED_WRAPPER_DIRS[@]}"})

  hook::git_resolve_subcommand "$HOOK_GITINV_GI" "${HOOK_GITINV_WORDS[@]}" || return 2
  HOOK_GITINV_SUB="$HOOK_GIT_SUB"
  HOOK_GITINV_SUB_IDX=$HOOK_GIT_SUB_IDX
  HOOK_GITINV_CONFIG_VALUES=(${HOOK_GIT_CONFIG_VALUES[@]+"${HOOK_GIT_CONFIG_VALUES[@]}"})
  HOOK_GITINV_CONFIG_KINDS=(${HOOK_GIT_CONFIG_VALUE_KINDS[@]+"${HOOK_GIT_CONFIG_VALUE_KINDS[@]}"})

  hook::git_alias_expansion "$HOOK_GITINV_SUB"
  case $? in
  0)
    HOOK_GITINV_ALIAS_TERM="inline"
    HOOK_GITINV_ALIAS_EXPS=(${HOOK_GIT_ALIAS_EXPS[@]+"${HOOK_GIT_ALIAS_EXPS[@]}"})
    ;;
  2) HOOK_GITINV_ALIAS_TERM="config-env" ;;
  *) ;;
  esac
  return 0
}

# git ignores an alias that hides an existing command, except a deprecated one:
# https://git-scm.com/docs/git-config#Documentation/git-config.txt-alias
hook::git_subcommand_ignores_alias() {
  case "$1" in
  add | am | annotate | apply | archive | bisect | blame | branch | bundle | \
    cat-file | check-attr | check-ignore | check-mailmap | check-ref-format | checkout | \
    checkout-index | cherry | cherry-pick | clean | clone | column | commit | commit-graph | \
    commit-tree | config | describe | diff | diff-files | diff-index | diff-tree | \
    difftool | fetch | for-each-ref | format-patch | fsck | gc | grep | hash-object | help | \
    init | interpret-trailers | log | ls-files | ls-remote | ls-tree | merge | \
    merge-base | mv | notes | pull | push | range-diff | rebase | reflog | remote | repack | \
    replace | reset | restore | rev-list | rev-parse | revert | rm | shortlog | show | \
    show-ref | sparse-checkout | stash | status | switch | symbolic-ref | tag | \
    update-ref | version | worktree)
    return 0
    ;;
  *) return 1 ;;
  esac
}

hook::git_effective_dir_to() {
  # shellcheck disable=SC2178  # nameref to the caller's string variable
  local -n _ed_out="$1"
  shift
  local base="${HOOK_EFFECTIVE_BASE:-${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}}" i n=$# arg
  local -a a=("$@")
  for ((i = 0; i + 1 < n; i++)); do
    [[ "${a[i]}" == "-C" ]] || continue
    arg="${a[++i]}"
    [[ "$arg" == /* || "$arg" =~ ^[A-Za-z]:[\/] ]] || arg="$base/$arg"
    base="$arg"
  done
  _ed_out="$base"
}

hook::git_alias_reparse_to() {
  # shellcheck disable=SC2178  # nameref to the caller's string variable
  local -n _gar_out="$1"
  local body="${2#!}" a q
  shift 2
  for a in "$@"; do
    printf -v q '%q' "$a"
    body+=" $q"
  done
  _gar_out="$body"
}

# shellcheck disable=SC2154  # HOOK_ALIAS_SEEN / HOOK_SHELL_ALIAS_SEEN are the caller's analysis state, read unset-safely below
hook::git_alias_admit() {
  local kind="$1" key q w
  shift
  if [[ -z "${HOOK_ALIAS_ADMIT_ARMED:-}" ]]; then
    declare -gA HOOK_ALIAS_MEMO=()
    HOOK_ALIAS_WORK=0
    HOOK_ALIAS_ADMIT_ARMED=1
  fi
  local -a _gaa_seen=(${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"})
  local -a _gaa_shell_seen=(${HOOK_SHELL_ALIAS_SEEN[@]+"${HOOK_SHELL_ALIAS_SEEN[@]}"})
  printf -v q '%q' "${HOOK_EFFECTIVE_BASE-}"
  key="$kind"$'\n'"$q"$'\n'"${#_gaa_seen[@]}"$'\n'"${#_gaa_shell_seen[@]}"$'\n'
  for w in ${_gaa_seen[@]+"${_gaa_seen[@]}"} ${_gaa_shell_seen[@]+"${_gaa_shell_seen[@]}"} "$@"; do
    printf -v q '%q' "$w"
    key+="$q"$'\n'
  done
  [[ -n "${HOOK_ALIAS_MEMO[$key]+x}" ]] && return 1
  HOOK_ALIAS_MEMO["$key"]=1
  ((++HOOK_ALIAS_WORK <= ${HOOK_ALIAS_WORK_MAX:-128})) && return 0
  return 2
}

hook::reset_analysis_state() {
  unset HOOK_ALIAS_ADMIT_ARMED HOOK_ALIAS_MEMO HOOK_ALIAS_WORK
  unset HOOK_ALIAS_SEEN HOOK_SHELL_ALIAS_SEEN HOOK_EFFECTIVE_BASE
}

hook::_bps_chars() {
  [[ "${LC_ALL-}" == C ]] || {
    hook::_c_locale hook::_bps_chars "$@"
    return
  }
  local __hu_s="$1" __hu_n=${#1} __hu_o1 __hu_o2 __hu_j __hu_big __hu_bn __hu_blk __hu_bl
  chars=()
  for ((__hu_o1 = 0; __hu_o1 < __hu_n; __hu_o1 += 4096)); do
    __hu_big=${__hu_s:__hu_o1:4096}
    __hu_bn=${#__hu_big}
    for ((__hu_o2 = 0; __hu_o2 < __hu_bn; __hu_o2 += 64)); do
      __hu_blk=${__hu_big:__hu_o2:64}
      __hu_bl=${#__hu_blk}
      for ((__hu_j = 0; __hu_j < __hu_bl; __hu_j++)); do
        chars+=("${__hu_blk:__hu_j:1}")
      done
    done
  done
}

hook::bash_parse_segments() {
  hook::bash_parse_segments_uncached "$@"
}

hook::bash_parse_segments_uncached() {
  hook::bash_parse_segments_shfmt "$1" "$2"
}

# shellcheck disable=SC2016  # jq program, not a shell expansion
HOOK_BPS_JQ='
def q: @sh | gsub("\n"; "\u0027$\u0027\\n\u0027\u0027") | gsub("\r"; "\u0027$\u0027\\r\u0027\u0027");
def span: ["S", "\(.Pos.Offset):\(.End.Offset)"];
def lit_text: gsub("\\\\\n"; "") | gsub("(?s)\\\\(?<c>.)"; "\(.c)");
def dq_text: gsub("\\\\\n"; "") | gsub("\\\\(?<c>[\"\\\\$`])"; "\(.c)");
def pieces:
  [.Parts[]? |
    if .Type == "Lit" then ["L", (.Value | lit_text)]
    elif .Type == "SglQuoted" then (if .Dollar then ["A", (.Value // "")] else ["L", (.Value // "")] end)
    elif .Type == "DblQuoted" then
      (.Parts[]? | if .Type == "Lit" then ["L", (.Value | dq_text)] else span end)
    else span end];
# shfmt drops a backslash-newline from Value, so a span longer than its text held one.
def has_esc: any(.Parts[]?; .Type == "Lit" and ((.Value | contains("\\")) or (.End.Offset - .Pos.Offset) != (.Value | utf8bytelength)));
def has_plain: any(.Parts[]?; .Type != "SglQuoted" and .Type != "DblQuoted");
def has_quoted: any(.Parts[]?; .Type == "SglQuoted" or .Type == "DblQuoted");
def prov: if (has_quoted or has_esc) then (if (has_quoted and (has_plain | not)) then 2 else 1 end) else 0 end;
def emit($q; $ps): [$q, ($ps | length)] + ($ps | add // []);
def word: emit(prov; pieces);
def textword($s): emit(0; [["L", $s]]);
def spanword: emit(0; [span]);
def assign:
  if .Array != null then spanword
  elif .Naked then
    (if .Name then textword(.Name.Value) elif .Value then (.Value | word) else spanword end)
  else
    (.Value // {Parts: []}) as $v
    | emit(($v | prov); [["S", "\(.Pos.Offset):\((.Value.Pos.Offset // .End.Offset))"]] + ($v | pieces))
  end;
def closer:
  {Block: "}", Subshell: ")", IfClause: "fi", WhileClause: "done", ForClause: "done", CaseClause: "esac"}[.Type] // ")";
def argv:
  if . == null then []
  elif .Type == "CallExpr" then
    [((.Assigns // [])[] | {o: .Pos.Offset, w: assign}), ((.Args // [])[] | {o: .Pos.Offset, w: word})]
    | sort_by(.o) | map(.w)
  elif .Type == "DeclClause" then [textword(.Variant.Value)] + [(.Args // [])[] | assign]
  elif .Type == "LetClause" then [textword("let")] + [(.Exprs // [])[] | spanword]
  elif .Type == "TestClause" then [textword("[["), (.X | spanword), textword("]]")]
  elif .Type == "ForClause" and .Loop.Type == "WordIter" then
    [textword("for"), textword(.Loop.Name.Value), textword("in")] + [(.Loop.Items // [])[] | word]
  elif .Type == "CaseClause" then [textword("case"), (.Word | word), textword("in")]
  else [] end;
def op: if . == "&>" then ">" elif . == "&>>" then ">>" else . end;
def opaque: if (.Parts | length) == 1 and .Parts[0].Type == "ProcSubst" then 1 else 0 end;
def redir: [(.Op | op), (.N.Value // ""), (.Word | prov), (.Word | opaque)] + (.Word | word);
def stmt:
  (.Cmd | argv) as $a
  | (.Redirs // []) as $r
  | (if ($a | length) > 0 then $a
     elif (.Cmd != null and ($r | length) > 0) then [textword(.Cmd | closer)]
     else [] end) as $w
  | if ($w | length) == 0 then empty
    else {o: .Pos.Offset, t: (["G", ($w | length), ($r | length)] + ($w | add) + ([$r[] | redir] | add // []))} end;
def strip_q: [.Parts[]? |
    if .Type == "Lit" then (.Value | lit_text)
    else (.Value // ([.Parts[]?.Value] | join(""))) end] | join("");
[.. | objects] as $all
| [$all[] | select(.Hdoc.Pos? != null) | [.Hdoc.Pos.Offset, .Hdoc.End.Offset]] as $hb
# A command inside a here-doc body comes after the top-level ones, so a callback
# that reads the segment before (a pipe into a shell) still reads the top-level one.
| ([$all[] | select(has("Cmd") or has("Redirs")) | select(has("Type") | not) | stmt
    | .k = (.o as $o | if any($hb[]; $o >= .[0] and $o < .[1]) then 1 else 0 end)]
   | sort_by([.k, .o]) | map(.t) | add // [])
  + ([$all[] | select(.Op == "<<" or .Op == "<<-")
     | {o: .OpPos.Offset,
        t: ["H", (.Hdoc.Pos.Offset // -1), .OpPos.Offset,
            (if (.Word | has_quoted or has_esc) then 1 else 0 end),
            (if .Op == "<<-" then 1 else 0 end), (.Word | strip_q)]}]
     | sort_by(.o) | map(.t) | add // [])
  + (if any($all[]; .Type == "ExtGlob") then ["E"] else [] end)
  + ([$all[] | select(.Array != null) | ["Y", .End.Offset]] | sort_by(.[1]) | add // [])
  + ([$all[] | select(.Type == "CmdSubst" and .Backquotes)
      | ["B", .Pos.Offset, .End.Offset,
         (if any(.. | objects; .Op == "<<" or .Op == "<<-") then 1 else 0 end)]] | add // [])
| map(tostring | q) | join(" ")'

HOOK_BPS_TIMEOUT=5

HOOK_BPS_MAX_PARSES=64

HOOK_BPS_FAIL_OPEN=0

HOOK_BPS_MEMO=0
HOOK_BPS_MEMO_KEY=()
HOOK_BPS_MEMO_VAL=()
# shellcheck disable=SC2030,SC2031  # pipefail belongs to this subshell
hook::_bps_shfmt_to() {
  local __hu_bs_out __hu_bs_st __hu_bs_i
  HOOK_BPS_FAIL=""
  if ((HOOK_BPS_MEMO)); then
    for ((__hu_bs_i = 0; __hu_bs_i < ${#HOOK_BPS_MEMO_KEY[@]}; __hu_bs_i++)); do
      if [[ "${HOOK_BPS_MEMO_KEY[__hu_bs_i]}" == "$2" ]]; then
        printf -v "$1" '%s' "${HOOK_BPS_MEMO_VAL[__hu_bs_i]}"
        return 0
      fi
    done
  fi
  hash shfmt 2>/dev/null || { [[ -x "${HOME:-}/.local/bin/shfmt" ]] && hash -p "$HOME/.local/bin/shfmt" shfmt; } || {
    HOOK_BPS_FAIL="shfmt is not on PATH"
    hook::_bps_install_note
    return 1
  }
  hash jq 2>/dev/null || {
    HOOK_BPS_FAIL="jq is not on PATH"
    return 1
  }
  __hu_bs_out=$(
    set -o pipefail
    {
      printf '%s' "$2" | {
        shfmt -ln bash --to-json <&0 2>/dev/null >&3 &
        printf '%s\n' "$!"
        wait "$!"
        printf '%s\n' "$?"
      } 2>/dev/null | {
        read -r __hu_bs_p
        read -r -t "${HOOK_BPS_TIMEOUT:-5}" __hu_bs_rc && exit "$__hu_bs_rc"
        kill "$__hu_bs_p" 2>/dev/null
        exit 142
      }
    } 3>&1 | jq -j "$HOOK_BPS_JQ" 2>/dev/null
  ) || {
    __hu_bs_st=$?
    if ((__hu_bs_st > 128)); then
      HOOK_BPS_FAIL="shfmt ran past ${HOOK_BPS_TIMEOUT:-5} s"
    else
      __hu_bs_out=$(printf '%s' "$2" | shfmt -ln bash 2>&1 >/dev/null)
      __hu_bs_out=${__hu_bs_out%%$'\n'*}
      if [[ -n "$__hu_bs_out" ]]; then
        HOOK_BPS_FAIL="shfmt rejects it as bash: $__hu_bs_out"
      else
        HOOK_BPS_FAIL="shfmt or jq failed (status $__hu_bs_st)"
      fi
    fi
    return 1
  }
  __hu_bs_out=${__hu_bs_out%$'\r'}
  if ((HOOK_BPS_MEMO)); then
    HOOK_BPS_MEMO_KEY+=("$2")
    HOOK_BPS_MEMO_VAL+=("$__hu_bs_out")
  fi
  printf -v "$1" '%s' "$__hu_bs_out"
}

HOOK_BPS_INSTALL_NOTE='.local/state/claude-guardrails/shfmt-install-failed'

hook::_bps_install_note() {
  local __hu_bn_l=""
  [[ -r "${HOME:-}/$HOOK_BPS_INSTALL_NOTE" ]] || return 0
  IFS= read -r __hu_bn_l <"$HOME/$HOOK_BPS_INSTALL_NOTE" || [[ -n "$__hu_bn_l" ]]
  [[ -n "$__hu_bn_l" ]] && HOOK_BPS_FAIL+="; the session's shfmt install failed: $__hu_bn_l"
  return 0
}

# shellcheck disable=SC2154  # __hu_bcmd and __hu_bspan are hook::bash_parse_segments_shfmt's
hook::_bps_refuse() {
  ((${HOOK_BPS_FAIL_OPEN:-0})) && exit 0
  local __hu_br_m="BLOCKED: the guard reads a command through shfmt and got no parse (${HOOK_BPS_FAIL:-no reason recorded}), so it cannot check this call. Fix the syntax, or install shfmt and jq, then reissue the call."
  local __hu_br_k=shfmt-unparsable __hu_br_x __hu_br_s=${HOOK_BPS_SPAN:-}
  if [[ -n "${__hu_bspan:-}" ]]; then
    if [[ -n "$__hu_br_s" ]]; then
      __hu_br_s+=", read again as $__hu_bspan"
    else
      __hu_br_s="hook-utils: $__hu_bspan"
    fi
  fi
  if [[ -n "$__hu_br_s" ]]; then
    __hu_br_x=${__hu_bcmd:0:256}
    __hu_br_x=${__hu_br_x//$'\n'/ }
    __hu_br_x=${__hu_br_x//[[:cntrl:]]/}
    ((${#__hu_br_x} > 60)) && __hu_br_x="${__hu_br_x:0:60}..."
    __hu_br_m="BLOCKED: the guard reads text it lifted from the command through shfmt and got no parse (${HOOK_BPS_FAIL:-no reason recorded}), so it cannot check this call. Lifted text: $__hu_br_s. A line:col in that reason counts from the start of that text, not of the command; the text begins: \"$__hu_br_x\". Fix the syntax there, or install shfmt and jq, then reissue the call."
    __hu_br_k=shfmt-unparsable-span
  fi
  if declare -F guard::say_once >/dev/null; then
    guard::say_once "$__hu_br_k" "$__hu_br_m"
  else
    printf '%s\n' "$__hu_br_m" >&2
  fi
  exit 2
}

# shellcheck disable=SC2154  # __hu_bt, __hu_bi and __hu_bcmd are hook::_bps_tree_decode's
hook::_bps_tree_word() {
  local __hu_bn __hu_bv __hu_btag __hu_bansi
  __hu_bq=${__hu_bt[__hu_bi++]}
  __hu_bn=${__hu_bt[__hu_bi++]}
  __hu_bw=""
  while ((__hu_bn-- > 0)); do
    __hu_btag=${__hu_bt[__hu_bi++]}
    __hu_bv=${__hu_bt[__hu_bi++]}
    case "$__hu_btag" in
    L) __hu_bw+=$__hu_bv ;;
    A)
      hook::ansi_c_decode_to __hu_bansi "$__hu_bv"
      __hu_bw+=$__hu_bansi
      ;;
    *) __hu_bw+=${__hu_bcmd:${__hu_bv%:*}:$((${__hu_bv#*:} - ${__hu_bv%:*}))} ;;
    esac
  done
}

# shellcheck disable=SC2154,SC2034  # the __hu_b* names are hook::bash_parse_segments_shfmt's
hook::_bps_tree_decode() {
  local __hu_bi=0 __hu_bo __hu_bq __hu_bw __hu_bk __hu_bn=${#__hu_bt[@]} __hu_br __hu_bj __hu_bs __hu_bl __hu_bd __hu_be __hu_bc __hu_bp __hu_bstrip __hu_bquoted
  local __hu_bcn=${#__hu_bcmd}
  __hu_bp=0
  while ((__hu_bi < __hu_bn)); do
    case "${__hu_bt[__hu_bi++]}" in
    G)
      __hu_bk=${__hu_bt[__hu_bi++]}
      __hu_br=${__hu_bt[__hu_bi++]}
      __hu_ac+=("$__hu_bk")
      __hu_rc+=("$__hu_br")
      for ((__hu_bj = 0; __hu_bj < __hu_bk; __hu_bj++)); do
        hook::_bps_tree_word
        __hu_wd+=("$__hu_bw")
        __hu_wq+=("$__hu_bq")
      done
      for ((__hu_bj = 0; __hu_bj < __hu_br; __hu_bj++)); do
        __hu_rop+=("${__hu_bt[__hu_bi++]}")
        __hu_rfd+=("${__hu_bt[__hu_bi++]}")
        __hu_bs=${__hu_bt[__hu_bi++]}
        __hu_ro+=("${__hu_bt[__hu_bi++]}")
        hook::_bps_tree_word
        __hu_rtg+=("$__hu_bw")
        ((__hu_bs)) && __hu_bs=1
        __hu_rq+=("$__hu_bs")
      done
      ;;
    H)
      __hu_bs=${__hu_bt[__hu_bi++]}
      __hu_bo=${__hu_bt[__hu_bi++]}
      __hu_bquoted=${__hu_bt[__hu_bi++]}
      __hu_bstrip=${__hu_bt[__hu_bi++]}
      __hu_bd=${__hu_bt[__hu_bi++]}
      if ((__hu_bs < 0)); then
        __hu_be=${__hu_bcmd:__hu_bo}
        __hu_be=${__hu_be%%$'\n'*}
        __hu_bs=$((__hu_bo + ${#__hu_be} + 1))
        ((__hu_bp > __hu_bs)) && __hu_bs=$__hu_bp
      fi
      __hu_be=$__hu_bs
      __hu_bc=0
      while ((__hu_be < __hu_bcn)); do
        __hu_bl=${__hu_bcmd:__hu_be}
        __hu_bl=${__hu_bl%%$'\n'*}
        __hu_be=$((__hu_be + ${#__hu_bl} + 1))
        if ((__hu_bstrip)); then
          while [[ "$__hu_bl" == $'\t'* ]]; do __hu_bl=${__hu_bl#?}; done
        fi
        if [[ "$__hu_bl" == "$__hu_bd" ]]; then
          __hu_bc=1
          break
        fi
      done
      ((__hu_be > __hu_bcn)) && __hu_be=$__hu_bcn
      __hu_bp=$__hu_be
      __hu_hs+=("$__hu_bs")
      __hu_hb+=("$__hu_bs $__hu_be $__hu_bquoted $__hu_bc $__hu_bd")
      if ((!__hu_bquoted)); then
        __hu_bl=${__hu_bcmd:__hu_bs:__hu_be-__hu_bs}
        if [[ "$__hu_bl" == *$'\\\n'* ]]; then
          ((__hu_bstrip)) && __hu_bq='<<-' || __hu_bq='<<'
          __hu_bt_more+=(": $__hu_bq$__hu_bd"$'\n'"${__hu_bl//$'\\\n'/}")
        fi
      fi
      ;;
    B)
      __hu_bs=${__hu_bt[__hu_bi++]}
      __hu_be=${__hu_bt[__hu_bi++]}
      __hu_bc=${__hu_bt[__hu_bi++]}
      if ((__hu_bc)); then
        HOOK_BPS_FAIL="a here-doc opened inside backticks, which bash reads differently"
        return 1
      fi
      for __hu_bj in ${__hu_hs[@]+"${__hu_hs[@]}"}; do
        if ((__hu_bj > __hu_bs && __hu_bj < __hu_be)); then
          HOOK_BPS_FAIL="a here-doc body that starts inside backticks, which bash reads differently"
          return 1
        fi
      done
      __hu_bl=${__hu_bcmd:__hu_bs+1:__hu_be-__hu_bs-2}
      __hu_bd=${__hu_bl//\\\\/}
      __hu_bd=${__hu_bd//\\\`/}
      if [[ "$__hu_bd" == *\`* ]]; then
        HOOK_BPS_FAIL="backticks bash would end at a different backtick"
        return 1
      fi
      if [[ "$__hu_bl" == *\\\`* ]]; then
        __hu_bl=${__hu_bl//\\\\/$'\x01'}
        __hu_bl=${__hu_bl//\\\`/\`}
        __hu_bl=${__hu_bl//\\\$/\$}
        __hu_bt_more+=("${__hu_bl//$'\x01'/\\}")
      fi
      ;;
    E) __hu_bext=1 ;;
    Y)
      __hu_bs=${__hu_bt[__hu_bi++]}
      if [[ "${__hu_bcmd:__hu_bs:1}" == '#' ]]; then
        __hu_sp=${__hu_sp:-$__hu_bcmd}
        __hu_sp=${__hu_sp:0:__hu_bs+__hu_bsshift}';_'${__hu_sp:__hu_bs+__hu_bsshift+1}
        __hu_spins+=($((__hu_bs + __hu_bsshift)))
        ((__hu_bsshift += 1))
      fi
      ;;
    *)
      HOOK_BPS_FAIL="a parse tree entry the reader does not know"
      return 1
      ;;
    esac
  done
}

hook::_bps_hd_check() {
  local __hu_km=$1 __hu_ke __hu_kh __hu_ks __hu_kn __hu_ki __hu_kc __hu_kf=0 __hu_kb=0
  shift 2
  for __hu_ke in ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}; do
    __hu_kb=$((__hu_kb + 1))
    [[ "$__hu_km" == joined ]] && ((__hu_kb == 1)) && continue
    [[ "$__hu_km" == map ]] || {
      __hu_kf=0
      break
    }
    __hu_ks=${__hu_ke%% *}
    __hu_ke=${__hu_ke#* }
    __hu_kn=${__hu_ke%% *}
    __hu_kc=0
    for __hu_ki in "$@"; do ((__hu_ki < __hu_ks)) && __hu_kc=$((__hu_kc + 1)); done
    __hu_ks=$((__hu_ks - __hu_kc))
    __hu_kc=0
    for __hu_ki in "$@"; do ((__hu_ki < __hu_kn)) && __hu_kc=$((__hu_kc + 1)); done
    __hu_kn=$((__hu_kn - __hu_kc))
    __hu_kf=0
    for __hu_kh in ${__hu_hb[@]+"${__hu_hb[@]}"}; do
      [[ "$__hu_kh" == "$__hu_ks $__hu_kn "* ]] && {
        __hu_kf=1
        break
      }
    done
    ((__hu_kf)) || break
  done
  ((__hu_kb == 0 || __hu_kf)) && return 0
  [[ "$__hu_km" == joined ]] && ((__hu_kb == 1)) && return 0
  HOOK_BPS_FAIL="a here-doc only a second reading of the command sees"
  ((__hu_bsoft)) && return 1
  hook::_bps_refuse
}

# shellcheck disable=SC2034  # HOOK_SEG_* are read by the callback's caller
hook::bash_parse_segments_shfmt() {
  local __hu_bcmd=$1 __hu_bcb=$2 __hu_bsoft=${3:-0} __hu_bspan=${4:-} __hu_bout=""
  local __hu_sp="" __hu_bsshift=0 __hu_bext=0
  local -a __hu_spins=()
  if [[ -z "${__hu_bps_in:-}" ]]; then
    local __hu_bps_in=1
    HOOK_BPS_PARSES=0
  fi
  HOOK_BPS_PARSES=$((${HOOK_BPS_PARSES:-0} + 1))
  if ((HOOK_BPS_PARSES > HOOK_BPS_MAX_PARSES)); then
    HOOK_BPS_FAIL="more than $HOOK_BPS_MAX_PARSES parses for one command (nested second readings)"
    hook::_bps_refuse
  fi
  local -a __hu_bt=() __hu_ac=() __hu_rc=() __hu_wd=() __hu_wq=() __hu_rop=() __hu_rfd=() __hu_rtg=() __hu_rq=() __hu_ro=() __hu_hb=() __hu_hs=() __hu_bt_more=()
  if ! hook::_bps_shfmt_to __hu_bout "$__hu_bcmd"; then
    ((__hu_bsoft)) && return 1
    hook::_bps_refuse
  fi
  eval "__hu_bt=($__hu_bout)"
  hook::_c_locale hook::_bps_tree_decode || {
    ((__hu_bsoft)) && return 1
    hook::_bps_refuse
  }
  if ((__hu_bext)); then
    HOOK_BPS_FAIL="an extglob pattern, which shfmt and bash do not read the same way"
    hook::_bps_refuse
  fi
  local __hu_s __hu_w=0 __hu_r=0 __hu_a __hu_c __hu_x __hu_hm __hu_hl
  local -a __hu_argv=()
  for ((__hu_s = 0; __hu_s < ${#__hu_ac[@]}; __hu_s++)); do
    __hu_a=${__hu_ac[__hu_s]}
    __hu_c=${__hu_rc[__hu_s]}
    __hu_argv=("${__hu_wd[@]:__hu_w:__hu_a}")
    HOOK_SEG_WORD_QUOTED=("${__hu_wq[@]:__hu_w:__hu_a}")
    HOOK_SEG_REDIR_OP=(${__hu_rop[@]+"${__hu_rop[@]:__hu_r:__hu_c}"})
    HOOK_SEG_REDIR_FD=(${__hu_rfd[@]+"${__hu_rfd[@]:__hu_r:__hu_c}"})
    HOOK_SEG_REDIR_TARGET=(${__hu_rtg[@]+"${__hu_rtg[@]:__hu_r:__hu_c}"})
    HOOK_SEG_REDIR_QUOTED=(${__hu_rq[@]+"${__hu_rq[@]:__hu_r:__hu_c}"})
    HOOK_SEG_REDIR_OPAQUE=(${__hu_ro[@]+"${__hu_ro[@]:__hu_r:__hu_c}"})
    __hu_w=$((__hu_w + __hu_a))
    __hu_r=$((__hu_r + __hu_c))
    "$__hu_bcb" "${__hu_argv[@]}"
  done
  HOOK_SEG_WORD_QUOTED=()
  HOOK_SEG_REDIR_OP=()
  HOOK_SEG_REDIR_FD=()
  HOOK_SEG_REDIR_TARGET=()
  HOOK_SEG_REDIR_QUOTED=()
  HOOK_SEG_REDIR_OPAQUE=()
  if [[ -n "$__hu_sp" ]]; then
    HOOK_HEREDOC_BODIES=()
    hook::bash_parse_segments_shfmt "$__hu_sp" "$__hu_bcb" "$__hu_bsoft" "$__hu_bspan" || return 1
    hook::_bps_hd_check map "$__hu_sp" ${__hu_spins[@]+"${__hu_spins[@]}"} || return 1
  fi
  for __hu_x in ${__hu_bt_more[@]+"${__hu_bt_more[@]}"}; do
    HOOK_HEREDOC_BODIES=()
    __hu_hm=none
    __hu_hl="the text inside backticks, its escaped backticks, dollars and backslashes unescaped"
    if [[ "$__hu_x" == ': <<'* ]]; then
      __hu_hm=joined
      __hu_hl="an unquoted here-doc body, its backslash-newlines joined, after a \`: <<DELIMITER\` first line"
    fi
    hook::bash_parse_segments_shfmt "$__hu_x" "$__hu_bcb" "$__hu_bsoft" "$__hu_hl" || return 1
    hook::_bps_hd_check "$__hu_hm" "$__hu_x" || return 1
  done
  # Set last: a callback's own parse would overwrite it.
  # shellcheck disable=SC2034  # result global is consumed by the sourcing guard
  HOOK_HEREDOC_BODIES=(${__hu_hb[@]+"${__hu_hb[@]}"})
  return 0
}

hook::findings_encode_to() {
  local __hu_fe_json='[]'
  if [[ -n "$2" ]] && hook::telemetry_enabled; then
    __hu_fe_json=$(printf '%s' "$2" | jq -R . | jq -s . 2>/dev/null) ||
      __hu_fe_json='[]'
  fi
  printf -v "$1" '%s' "$__hu_fe_json"
}

hook::findings_to() {
  local __hu_ft_dest="$1" __hu_ft_ctx="$2" __hu_ft_out="$3" __hu_ft_fd=""
  local __hu_ft_max=0 __hu_ft_more="" __hu_ft_delta=0 __hu_ft_in="" __hu_ft_file=""
  shift 3
  if (($#)) && [[ "$1" != --* ]]; then
    __hu_ft_fd="$1"
    shift
  fi
  while (($#)); do
    case "$1" in
    --max)
      __hu_ft_max="$2"
      shift 2
      ;;
    --more)
      __hu_ft_more="$2"
      shift 2
      ;;
    --delta)
      __hu_ft_delta=1
      __hu_ft_in="$2"
      __hu_ft_file="$3"
      shift 3
      ;;
    *) shift ;;
    esac
  done
  [[ "$__hu_ft_max" =~ ^[0-9]+$ ]] || __hu_ft_max=0
  local __hu_ft_raw="" __hu_ft_line __hu_ft_n=0
  while IFS= read -r __hu_ft_line; do
    [[ -n "$__hu_ft_line" ]] || continue
    __hu_ft_n=$((__hu_ft_n + 1))
    __hu_ft_raw+="$__hu_ft_line"$'\n'
    ((__hu_ft_max == 0 || __hu_ft_n <= __hu_ft_max)) && __hu_ft_ctx+=$'\n'"  $__hu_ft_line"
  done <<<"$__hu_ft_out"
  if ((__hu_ft_max > 0 && __hu_ft_n > __hu_ft_max)); then
    __hu_ft_ctx+=$'\n'"  ... and $((__hu_ft_n - __hu_ft_max)) more${__hu_ft_more:+ ($__hu_ft_more)}"
  fi
  [[ -n "$__hu_ft_fd" ]] && hook::findings_encode_to "$__hu_ft_fd" "$__hu_ft_raw"
  if ((__hu_ft_delta)); then
    local __hu_ft_s __hu_ft_a __hu_ft_dir __hu_ft_key __hu_ft_prev=""
    ((__hu_ft_n)) || __hu_ft_ctx=""
    hook::session_agent_to __hu_ft_s __hu_ft_a "$__hu_ft_in"
    if hook::_state_dir_to __hu_ft_dir finding-digests; then
      hook::_file_key_to __hu_ft_key "$__hu_ft_file"
      local __hu_ft_rec="$__hu_ft_dir/${__hu_ft_s}.${__hu_ft_a}.${__hu_ft_key}"
      if ((__hu_ft_n == 0)); then
        [[ -f "$__hu_ft_rec" ]] && { rm -f "$__hu_ft_rec" 2>/dev/null || true; }
      else
        local __hu_ft_now="max=$__hu_ft_max"$'\n'"$__hu_ft_file"$'\n'"$__hu_ft_raw"
        [[ -f "$__hu_ft_rec" ]] && { IFS= read -r -d '' __hu_ft_prev <"$__hu_ft_rec" || true; }
        if [[ "$__hu_ft_prev" == "$__hu_ft_now" ]]; then
          __hu_ft_ctx=""
        else
          printf '%s' "$__hu_ft_now" 2>/dev/null >"$__hu_ft_rec" || true
        fi
      fi
    fi
  fi
  printf -v "$__hu_ft_dest" '%s' "$__hu_ft_ctx"
  return 0
}

hook::findings_digest_reset() {
  [[ "$1" =~ \"source\"[[:space:]]*:[[:space:]]*\"(compact|clear)\" ]] || return 0
  local __hu_fr_s __hu_fr_a
  hook::session_agent_to __hu_fr_s __hu_fr_a "$1"
  [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] || return 0
  local __hu_fr_recs=("${CLAUDE_PLUGIN_DATA%/}/finding-digests/${__hu_fr_s}".*)
  [[ -e "${__hu_fr_recs[0]}" ]] && { rm -f "${__hu_fr_recs[@]}" 2>/dev/null || true; }
  return 0
}

hook::tool_missing_notice_to() {
  printf 'PATH probed: %s\n' "${PATH:-<unset>}" >&2
  printf -v "$1" '%s' "$2 (the probe re-runs on every $3 edit; this notice does not repeat this session). Hooks read Claude Code's PATH, not your shell profile${4:-}"
}
