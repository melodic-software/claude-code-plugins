# shellcheck shell=bash
# Exit codes:
#   0  the hook runs
#   1  the hook is off
#   2  usage error

[[ -n "${_HOOK_ENABLED_LOADED:-}" ]] && return 0
readonly _HOOK_ENABLED_LOADED=1

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

hook_enabled::_no_repository_layer() {
  local root home
  hook_enabled::_posix_to root "$1"
  hook_enabled::_posix_to home "${HOME:-}"
  [[ -z "$root" ]] && return 0
  [[ -n "$home" ]] || return 1
  [[ "$root" == "$home" || "$home/" == "$root/"* ]]
}

hook_enabled::resolve() {
  local security=0 root="${CLAUDE_PROJECT_DIR:-}" home="docs/conventions" plugin key default option user file repo
  local -a positional=()
  while (($# > 0)); do
    case "$1" in
      --security)
        security=1
        shift
        ;;
      --root | --home)
        if (($# < 2)); then
          echo "hook-enabled: $1 requires a value" >&2
          return 2
        fi
        if [[ "$1" == --root ]]; then root="$2"; else home="$2"; fi
        shift 2
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  if ((${#positional[@]} != 3)); then
    echo "hook-enabled: usage: hook_enabled::resolve [--security] [--root DIR] [--home DIR] <plugin> <key> <true|false>" >&2
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

  hook_enabled::_map_to option "CLAUDE_PLUGIN_OPTION_$key" "$_HOOK_ENABLED_LOWER" "$_HOOK_ENABLED_UPPER"
  user="${!option:-}"
  case "$user" in
    "") ;;
    true) return 0 ;;
    false) ((security)) || return 1 ;;
    *) hook_enabled::_drop "$key" "$user" "$option" ;;
  esac

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
