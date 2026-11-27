# GENERATED from lib/hook-enabled.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# shellcheck shell=bash
# Exit codes:
#   0  the hook runs
#   1  the hook is off
#   2  usage error

[[ -n "${_HOOK_ENABLED_LOADED:-}" ]] && return 0
readonly _HOOK_ENABLED_LOADED=1
readonly _HOOK_ENABLED_SOURCE="${BASH_SOURCE[0]:-}"

readonly _HOOK_ENABLED_LOWER=abcdefghijklmnopqrstuvwxyz
readonly _HOOK_ENABLED_UPPER=ABCDEFGHIJKLMNOPQRSTUVWXYZ

hook_enabled::_map_to() {
  local __he_in="$2" __he_from="$3" __he_to="$4" __he_out="" __he_c __he_before __he_i
  for ((__he_i = 0; __he_i < ${#__he_in}; __he_i++)); do
    __he_c="${__he_in:__he_i:1}"
    __he_before="${__he_from%%"$__he_c"*}"
    if ((${#__he_before} < ${#__he_from})); then
      __he_out+="${__he_to:${#__he_before}:1}"
    else
      __he_out+="$__he_c"
    fi
  done
  printf -v "$1" '%s' "$__he_out"
}

hook_enabled::_posix_to() {
  local __he_p="${2//\\//}" __he_drive
  if [[ "$__he_p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    hook_enabled::_map_to __he_drive "${BASH_REMATCH[1]}" "$_HOOK_ENABLED_UPPER" "$_HOOK_ENABLED_LOWER"
    __he_p="/$__he_drive${BASH_REMATCH[2]-}"
  fi
  printf -v "$1" '%s' "${__he_p%/}"
}

hook_enabled::_drop() {
  local value="$2"
  ((${#value} <= 60)) || value="${value:0:60}..."
  printf 'hook-enabled: %s: dropped "%s" from %s; only an unquoted true or false is read\n' "$1" "$value" "$3" >&2
}

hook_enabled::_repo_value_to() {
  local __he_file="$2" __he_key="$3" __he_line __he_value="" __he_first=1
  printf -v "$1" '%s' ""
  if [[ -L "$__he_file" ]]; then
    printf 'hook-enabled: %s: skipped %s; a symlink, and the repository layer reads only regular files\n' "$__he_key" "$__he_file" >&2
    return 1
  fi
  [[ -f "$__he_file" && -r "$__he_file" ]] || return 1
  while IFS= read -r __he_line || [[ -n "$__he_line" ]]; do
    if ((__he_first)); then
      __he_line="${__he_line#$'\xEF\xBB\xBF'}"
      __he_first=0
    fi
    [[ "$__he_line" == "$__he_key:"* ]] || continue
    __he_value="${__he_line#"$__he_key:"}"
    __he_value="${__he_value%$'\r'}"
    __he_value="${__he_value%%#*}"
    __he_value="${__he_value#"${__he_value%%[![:space:]]*}"}"
    __he_value="${__he_value%"${__he_value##*[![:space:]]}"}"
    printf -v "$1" '%s' "$__he_value"
    return 0
  done <"$__he_file"
  return 1
}

hook_enabled::_install_to() {
  local __he_src="${_HOOK_ENABLED_SOURCE//\\//}" __he_rest __he_mkt __he_name
  printf -v "$1" '%s' ""
  printf -v "$2" '%s' ""
  [[ "$__he_src" == /* || "$__he_src" == [A-Za-z]:/* ]] || return 1
  [[ "$__he_src" == */plugins/cache/*/*/* ]] || return 1
  __he_rest="${__he_src#*/plugins/cache/}"
  __he_mkt="${__he_rest%%/*}"
  __he_rest="${__he_rest#*/}"
  __he_name="${__he_rest%%/*}"
  [[ -n "$__he_mkt" && -n "$__he_name" ]] || return 1
  printf -v "$1" '%s' "$__he_name@$__he_mkt"
  printf -v "$2" '%s' "${__he_src%%/plugins/cache/*}/settings.json"
}

hook_enabled::_option_to() {
  local __he_out
  command -v jq >/dev/null 2>&1 || return 1
  { __he_out="$(jq -j --arg id "$2" --arg k "$3" --arg name "${4-}" '
    [ (.pluginConfigs? // empty) | objects | to_entries[]
      | select(if $id != "" then .key == $id else (.key | startswith($name + "@")) end)
      | (.value.options[$k])?
      | if type == "boolean" then tostring elif type == "string" then . elif type == "null" then empty else tojson end ]
    | unique
    | if length == 1 then "v:" + .[0] elif length > 1 then "x:" else empty end')"; } 2>/dev/null || return 1
  __he_out="${__he_out%$'\r'}"
  if [[ "$__he_out" == x: ]]; then
    printf 'hook-enabled: %s: skipped %s; entries for more than one marketplace set different values\n' "$3" "${5-}" >&2
    return 1
  fi
  [[ "$__he_out" == v:* ]] || return 1
  printf -v "$1" '%s' "${__he_out#v:}"
}

hook_enabled::_user_settings_to() {
  local __he_dir="${CLAUDE_CONFIG_DIR:-}"
  printf -v "$1" '%s' ""
  if [[ -z "$__he_dir" ]]; then
    [[ -n "${HOME:-}" ]] || return 1
    __he_dir="$HOME/.claude"
  fi
  __he_dir="${__he_dir//\\//}"
  printf -v "$1" '%s' "${__he_dir%/}/settings.json"
}

hook_enabled::_settings_value_to() {
  local __he_key="$3" __he_name="${4-}" __he_id="" __he_file __he_from
  printf -v "$1" '%s' ""
  printf -v "$2" '%s' ""
  if [[ -n "$__he_name" ]]; then
    hook_enabled::_user_settings_to __he_file || return 1
    __he_from="pluginConfigs[\"$__he_name@*\"] in $__he_file"
  else
    hook_enabled::_install_to __he_id __he_file || return 1
    __he_from="pluginConfigs[\"$__he_id\"] in $__he_file"
  fi
  [[ -f "$__he_file" && -r "$__he_file" ]] || return 1
  hook_enabled::_option_to "$1" "$__he_id" "$__he_key" "$__he_name" "$__he_from" <"$__he_file" || return 1
  printf -v "$2" '%s' "$__he_from"
}

readonly _HOOK_ENABLED_MANAGED_DARWIN="/Library/Application Support/ClaudeCode/managed-settings.json"
readonly _HOOK_ENABLED_MANAGED_WINDOWS="C:/Program Files/ClaudeCode/managed-settings.json"
readonly _HOOK_ENABLED_MANAGED_LINUX="/etc/claude-code/managed-settings.json"
_HOOK_ENABLED_MANAGED_FILES=()
_HOOK_ENABLED_MANAGED_OWNER_CHECK=0

# Paths, precedence and drop-in order:
# https://code.claude.com/docs/en/managed-settings#split-a-file-based-policy-across-teams
hook_enabled::_managed_files() {
  local platform="" primary f LC_ALL=C
  _HOOK_ENABLED_MANAGED_FILES=()
  _HOOK_ENABLED_MANAGED_OWNER_CHECK=0
  { platform=$(uname -s); } 2>/dev/null || platform=""
  case "$platform" in
    Darwin) primary="$_HOOK_ENABLED_MANAGED_DARWIN" ;;
    MINGW* | MSYS* | CYGWIN*) primary="$_HOOK_ENABLED_MANAGED_WINDOWS" ;;
    Linux)
      primary="$_HOOK_ENABLED_MANAGED_LINUX"
      _HOOK_ENABLED_MANAGED_OWNER_CHECK=1
      ;;
    *) return 0 ;;
  esac
  [[ -f "$primary" ]] && _HOOK_ENABLED_MANAGED_FILES+=("$primary")
  for f in "${primary%/*}/managed-settings.d"/*.json; do
    [[ -f "$f" ]] && _HOOK_ENABLED_MANAGED_FILES+=("$f")
  done
  return 0
}

# Which platforms' managed directory a user can write:
# https://code.claude.com/docs/en/managed-settings#present-admin-documents
hook_enabled::_managed_read_to() {
  local __he_file="$3" __he_open="" __he_path="" __he_uid __he_mode __he_rest
  printf -v "$1" '%s' ""
  printf -v "$2" '%s' 1
  [[ -f "$__he_file" && -r "$__he_file" ]] || return 1
  if ! ((_HOOK_ENABLED_MANAGED_OWNER_CHECK)); then
    hook_enabled::_option_to "$1" "$4" "$5" "${6-}" "${7-}" <"$__he_file"
    return
  fi
  # shellcheck disable=SC2094 # both stats only read: the descriptor's file, then the path's own inode
  {
    __he_open="$(stat -L -c '%d:%i %u %a' /dev/fd/9 2>/dev/null)" || __he_open="" # portability-ok: GNU stat, reached only when uname -s is Linux
    __he_path="$(stat -c '%d:%i' -- "$__he_file" 2>/dev/null)" || __he_path=""    # portability-ok: GNU stat, reached only when uname -s is Linux
    hook_enabled::_option_to "$1" "$4" "$5" "${6-}" "${7-}" <&9 || return 1
  } 9<"$__he_file"
  read -r __he_rest __he_uid __he_mode <<<"$__he_open"
  if [[ -n "$__he_path" && "$__he_rest" == "$__he_path" && "$__he_uid" == 0 && "$__he_mode" =~ ^[0-7]+$ ]] &&
    ! ((8#$__he_mode & 8#022)) && { ((EUID == 0)) || [[ ! -w "$__he_file" ]]; }; then
    return 0
  fi
  printf -v "$2" '%s' 0
}

hook_enabled::_managed_value_to() {
  local __he_key="$3" __he_name="${4-}" __he_id="" __he_entry __he_user __he_f __he_v __he_trusted __he_have=1
  printf -v "$1" '%s' ""
  printf -v "$2" '%s' ""
  if [[ -n "$__he_name" ]]; then
    __he_entry="$__he_name@*"
  else
    hook_enabled::_install_to __he_id __he_user || return 1
    __he_entry="$__he_id"
  fi
  hook_enabled::_managed_files
  for __he_f in ${_HOOK_ENABLED_MANAGED_FILES[@]+"${_HOOK_ENABLED_MANAGED_FILES[@]}"}; do
    hook_enabled::_managed_read_to __he_v __he_trusted "$__he_f" "$__he_id" "$__he_key" "$__he_name" "pluginConfigs[\"$__he_entry\"] in $__he_f" || continue
    case "$__he_v" in
      true) ;;
      false)
        if ! ((__he_trusted)); then
          printf 'hook-enabled: %s: skipped false from %s; a managed file that turns a guard off must be root-owned and writable by no one else\n' "$__he_key" "$__he_f" >&2
          continue
        fi
        ;;
      *)
        hook_enabled::_drop "$__he_key" "$__he_v" "pluginConfigs[\"$__he_entry\"] in $__he_f"
        continue
        ;;
    esac
    printf -v "$1" '%s' "$__he_v"
    printf -v "$2" '%s' "pluginConfigs[\"$__he_entry\"] in $__he_f"
    __he_have=0
  done
  return "$__he_have"
}

hook_enabled::_no_repository_layer() {
  local root home
  hook_enabled::_posix_to root "$1"
  hook_enabled::_posix_to home "${HOME:-}"
  [[ -z "$root" ]] && return 0
  [[ -n "$home" ]] || return 1
  [[ "$root" == "$home" || "$home/" == "$root/"* ]]
}

hook_enabled::resolve() {
  local security=0 git_hook=0 root="${CLAUDE_PROJECT_DIR:-}" root_given=0 home="docs/conventions" plugin key default option user file repo setting setting_from name=""
  local -a positional=()
  while (($# > 0)); do
    case "$1" in
      --security)
        security=1
        shift
        ;;
      --git-hook)
        git_hook=1
        shift
        ;;
      --root | --home)
        if (($# < 2)); then
          echo "hook-enabled: $1 requires a value" >&2
          return 2
        fi
        if [[ "$1" == --root ]]; then
          root="$2"
          root_given=1
        else
          home="$2"
        fi
        shift 2
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  if ((${#positional[@]} != 3)); then
    echo "hook-enabled: usage: hook_enabled::resolve [--security] [--git-hook] [--root DIR] [--home DIR] <plugin> <key> <true|false>" >&2
    return 2
  fi
  plugin="${positional[0]}" key="${positional[1]}" default="${positional[2]}"
  if [[ ! "$plugin" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "hook-enabled: plugin name \"$plugin\" is not a plain name" >&2
    return 2
  fi
  if [[ ! "$key" =~ ^[a-z][a-z0-9_]*_enabled$ ]]; then
    echo "hook-enabled: key \"$key\" is not a snake_case <name>_enabled key" >&2
    return 2
  fi
  if [[ "$default" != true && "$default" != false ]]; then
    echo "hook-enabled: $key: plugin default \"$default\" is not true or false" >&2
    return 2
  fi

  if ((git_hook)); then
    name="$plugin"
    ((root_given)) || { root="$(git rev-parse --show-toplevel)"; } 2>/dev/null || root=""
  fi

  if ((security)) && hook_enabled::_managed_value_to setting setting_from "$key" "$name"; then
    [[ "$setting" == true ]]
    return
  fi

  if ((security || git_hook)) && hook_enabled::_settings_value_to setting setting_from "$key" "$name"; then
    case "$setting" in
      true) return 0 ;;
      false) return 1 ;;
      *) hook_enabled::_drop "$key" "$setting" "$setting_from" ;;
    esac
  fi

  if ! ((git_hook)); then
    hook_enabled::_map_to option "CLAUDE_PLUGIN_OPTION_$key" "$_HOOK_ENABLED_LOWER" "$_HOOK_ENABLED_UPPER"
    user="${!option:-}"
    case "$user" in
      "") ;;
      true) return 0 ;;
      false) ((security)) || return 1 ;;
      *) hook_enabled::_drop "$key" "$user" "$option" ;;
    esac
  fi

  if ! hook_enabled::_no_repository_layer "$root"; then
    file="${root%/}/${home%/}/$plugin.yaml"
    if hook_enabled::_repo_value_to repo "$file" "$key"; then
      case "$repo" in
        true) return 0 ;;
        false) ((security)) || return 1 ;;
        *) hook_enabled::_drop "$key" "$repo" "$file" ;;
      esac
    fi
  fi

  [[ "$default" == true ]]
}
