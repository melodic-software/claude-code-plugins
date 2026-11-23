# shellcheck shell=bash

[[ -n "${_LANE_STOP_GATE_LIB_LOADED:-}" ]] && return 0
readonly _LANE_STOP_GATE_LIB_LOADED=1

readonly GATE_ARM_ID_RE='^[A-Za-z0-9_-]{8,64}$'

# Arm-record lifetime outlasts the 30-day /loop expiry: https://code.claude.com/docs/en/changelog#2-1-330
# shellcheck disable=SC2034 # read by lane-stop-gate.sh and lane-stop-gate-arm.sh, not here
readonly GATE_ARM_TTL_DAYS=31

# Layout and id sanitization follow https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables
GATE_CONFIG_ROOT=""
GATE_PLUGIN_ID=""
GATE_PLUGIN_ID_SAFE=""
GATE_PLUGIN_NAME=""

gate_resolve_anchor() {
  local root="$1" rest marketplace name
  [[ -n "$root" && "$root" == */plugins/cache/*/*/* ]] || return 1
  rest="${root#*/plugins/cache/}"
  marketplace="${rest%%/*}"
  rest="${rest#*/}"
  name="${rest%%/*}"
  [[ -n "$marketplace" && -n "$name" ]] || return 1
  GATE_CONFIG_ROOT="${root%%/plugins/cache/*}"
  GATE_PLUGIN_ID="${name}@${marketplace}"
  GATE_PLUGIN_ID_SAFE="${GATE_PLUGIN_ID//[^A-Za-z0-9_-]/-}"
}

gate_plugin_root_to() {
  local __root
  case "$2" in
  /*) __root="$2/.." ;;
  ?:[/\\]*) __root="${2//\\//}/.." ;;
  *) __root=$(cd "$2/.." 2>/dev/null && pwd) ;;
  esac
  printf -v "$1" '%s' "$__root"
}

gate_resolve_plugin_name() {
  local manifest="$1/.claude-plugin/plugin.json" name
  [[ -f "$manifest" ]] || return 1
  { name=$(jq -r '.name | select(type == "string")'); } 2>/dev/null <"$manifest" || return 1
  [[ -n "$name" ]] || return 1
  GATE_PLUGIN_NAME="$name"
}


gate_resolve_install() {
  local root="$1"
  gate_resolve_anchor "$root" && return 0
  gate_resolve_plugin_name "$root"
}

gate_data_dir_to() {
  if [[ -n "$GATE_CONFIG_ROOT" ]]; then
    printf -v "$1" '%s/plugins/data/%s' "$GATE_CONFIG_ROOT" "$GATE_PLUGIN_ID_SAFE"
  else
    printf -v "$1" '%s' "${CLAUDE_PLUGIN_DATA:-}"
  fi
}

gate_trusted_data_dir_to() {
  [[ -n "$GATE_CONFIG_ROOT" ]] || return 1
  printf -v "$1" '%s/plugins/data/%s' "$GATE_CONFIG_ROOT" "$GATE_PLUGIN_ID_SAFE"
}

gate_arm_record_path_to() {
  local id="$2" dir
  [[ "$id" =~ $GATE_ARM_ID_RE ]] || return 1
  gate_trusted_data_dir_to dir || return 1
  printf -v "$1" '%s/lane-arms/%s' "$dir" "$id"
}
gate_arm_record_path() {
  local __gate_out
  gate_arm_record_path_to __gate_out "$1" || return 1
  printf '%s' "$__gate_out"
}

gate_arm_claim_path_to() {
  local rec
  gate_arm_record_path_to rec "$2" || return 1
  printf -v "$1" '%s.claim' "$rec"
}
gate_arm_claim_path() {
  local __gate_out
  gate_arm_claim_path_to __gate_out "$1" || return 1
  printf '%s' "$__gate_out"
}

gate_user_settings_file_to() {
  [[ -n "$GATE_CONFIG_ROOT" ]] || return 1
  printf -v "$1" '%s/settings.json' "$GATE_CONFIG_ROOT"
}

readonly GATE_MANAGED_PRIMARY_DARWIN="/Library/Application Support/ClaudeCode/managed-settings.json"
readonly GATE_MANAGED_PRIMARY_WINDOWS="C:/Program Files/ClaudeCode/managed-settings.json"
readonly GATE_MANAGED_PRIMARY_LINUX="/etc/claude-code/managed-settings.json"
GATE_MANAGED_FILES=()
GATE_MANAGED_FILES_LOADED=0
gate_managed_settings_files_load() {
  local primary platform=""
  GATE_MANAGED_FILES=()
  GATE_MANAGED_FILES_LOADED=1
  { platform=$(uname -s); } 2>/dev/null || platform=""
  case "$platform" in
  Darwin) primary="$GATE_MANAGED_PRIMARY_DARWIN" ;;
  MINGW* | MSYS* | CYGWIN*) primary="$GATE_MANAGED_PRIMARY_WINDOWS" ;;
  Linux) primary="$GATE_MANAGED_PRIMARY_LINUX" ;;
  *) return 0 ;;
  esac
  case "$primary" in
  /* | [A-Za-z]:[/\\]*) ;;
  *) return 0 ;;
  esac
  [[ -f "$primary" ]] && GATE_MANAGED_FILES+=("$primary")
  local dropin="${primary%/*}/managed-settings.d" f
  if [[ -d "$dropin" ]]; then
    for f in "$dropin"/*.json; do
      [[ -f "$f" ]] && GATE_MANAGED_FILES+=("$f")
    done
  fi
  return 0
}
gate_managed_settings_files() {
  local f
  gate_managed_settings_files_load
  for f in ${GATE_MANAGED_FILES[@]+"${GATE_MANAGED_FILES[@]}"}; do
    printf '%s\n' "$f"
  done
  return 0
}

# The file is opened by bash (`< file`), not by jq: a native jq on Windows
# cannot open an MSYS-style path, while a shell redirection always can.
# A jq that writes stdout in text mode turns each LF into CRLF, so a trailing CR is removed with the trailing newlines.
# shellcheck disable=SC2034 # result arrays are consumed by the sourcing hook
gate_settings_options_to() {
  local file="$1"
  shift
  GATE_FILE_OPT_HAVE=()
  GATE_FILE_OPT_VALUE=()
  local i
  for ((i = 0; i < $#; i++)); do
    GATE_FILE_OPT_HAVE[i]=0
    GATE_FILE_OPT_VALUE[i]=""
  done
  (($#)) || return 1
  [[ -f "$file" ]] || return 1
  [[ -n "$GATE_PLUGIN_ID" || -n "$GATE_PLUGIN_NAME" ]] || return 1
  local keys="" k
  for k in "$@"; do
    [[ "$k" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    keys+="${keys:+,}\"$k\""
  done
  local -a recs=()
  local rec
  {
    while IFS= read -r -d '' rec; do
      while [[ "$rec" == *[$'\r\n'] ]]; do rec="${rec%?}"; done
      recs+=("$rec")
    done < <(jq -j --arg id "$GATE_PLUGIN_ID" --arg n "$GATE_PLUGIN_NAME" --argjson keys "[$keys]" '
      [ (.pluginConfigs // {}) | to_entries[]
        | select(if $id != "" then .key == $id
                 else .key == $n or (.key | startswith($n + "@")) end)
        | .value.options ] as $opts
      | $keys[] as $k
      | ([ $opts[] | .[$k]
           | if type == "boolean" then (if . then "v:true" else "v:false" end)
             elif type == "string" then "v:" + .
             else empty end ] | last // "-")
      | (., ([0] | implode))')
  } 2>/dev/null <"$file"
  ((${#recs[@]} == $#)) || return 1
  local have=1
  for ((i = 0; i < $#; i++)); do
    [[ "${recs[i]}" == v:* ]] || continue
    GATE_FILE_OPT_HAVE[i]=1
    GATE_FILE_OPT_VALUE[i]="${recs[i]#v:}"
    have=0
  done
  return "$have"
}

gate_settings_option() {
  gate_settings_options_to "$1" "$2" || return 1
  ((GATE_FILE_OPT_HAVE[0])) || return 1
  printf '%s' "${GATE_FILE_OPT_VALUE[0]}"
}

# shellcheck disable=SC2034 # result arrays are consumed by the sourcing hook
gate_managed_options_to() {
  GATE_MANAGED_OPT_HAVE=()
  GATE_MANAGED_OPT_VALUE=()
  local i f have=1
  for ((i = 0; i < $#; i++)); do
    GATE_MANAGED_OPT_HAVE[i]=0
    GATE_MANAGED_OPT_VALUE[i]=""
  done
  ((GATE_MANAGED_FILES_LOADED)) || gate_managed_settings_files_load
  for f in ${GATE_MANAGED_FILES[@]+"${GATE_MANAGED_FILES[@]}"}; do
    gate_settings_options_to "$f" "$@" || continue
    for ((i = 0; i < $#; i++)); do
      ((GATE_FILE_OPT_HAVE[i])) || continue
      GATE_MANAGED_OPT_HAVE[i]=1
      GATE_MANAGED_OPT_VALUE[i]="${GATE_FILE_OPT_VALUE[i]}"
      have=0
    done
  done
  return "$have"
}

gate_managed_option() {
  GATE_MANAGED_FILES_LOADED=0
  gate_managed_options_to "$1" || return 1
  ((GATE_MANAGED_OPT_HAVE[0])) || return 1
  printf '%s' "${GATE_MANAGED_OPT_VALUE[0]}"
}

gate_epochseconds_is_clock() {
  ((BASH_VERSINFO[0] >= 5))
}

gate_epoch_seconds_to() {
  local __now=""
  if gate_epochseconds_is_clock; then
    __now="${EPOCHSECONDS-}"
  fi
  [[ "$__now" =~ ^[0-9]+$ ]] || { { __now=$(date +%s); } 2>/dev/null || __now=""; }
  printf -v "$1" '%s' "$__now"
}
