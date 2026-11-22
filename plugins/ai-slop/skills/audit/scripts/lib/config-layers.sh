# shellcheck shell=bash

_CONFIG_LAYERS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../lib" 2>/dev/null && pwd)"

# shellcheck source=../../../../lib/config-root.sh
source "$_CONFIG_LAYERS_LIB/config-root.sh"

resolve_config_layers() {
  local repo_root="$1" show_config="$2" old_user_cfg="${HOME:-/nonexistent}/.claude/ai-slop.json"
  local personal_cfg="" personal_present=0 conv_home home cfg
  CFG_LAYERS=()
  OLD_PATH_NOTE=""
  if [[ "$(config_root_classify "$repo_root")" == repo ]]; then
    conv_home="docs/conventions"
    if home="$(bash "$_CONFIG_LAYERS_LIB/resolve-convention-home.sh" --root "$repo_root" 2>/dev/null)" && [[ -n "$home" ]]; then
      conv_home="$home"
    fi
    cfg="$repo_root/$conv_home/ai-slop.yaml"
    [[ -f "$cfg" ]] && ! config_root_paths_same "$cfg" "$old_user_cfg" && CFG_LAYERS+=("$cfg")
    personal_cfg="$repo_root/$conv_home/ai-slop.local.yaml"
    [[ -f "$personal_cfg" ]] && ! config_root_paths_same "$personal_cfg" "$old_user_cfg" && personal_present=1
  fi
  if [[ "$personal_present" -eq 1 ]]; then
    CFG_LAYERS+=("$personal_cfg")
    [[ -f "$old_user_cfg" ]] &&
      OLD_PATH_NOTE="Warning: $old_user_cfg is an old path and not read, since $personal_cfg supplies the personal layer; /ai-slop:setup apply moves its settings into $personal_cfg and deletes it"
  elif [[ -f "$old_user_cfg" ]]; then
    CFG_LAYERS+=("$old_user_cfg")
    OLD_PATH_NOTE="Warning: $old_user_cfg is an old path, still read as the personal layer until it moves; /ai-slop:setup apply moves it to ${personal_cfg:-<home>/ai-slop.local.yaml in the repository} and deletes it"
  fi
  if [[ -n "$OLD_PATH_NOTE" && "$show_config" -ne 1 ]]; then
    echo "$OLD_PATH_NOTE" >&2
  fi
  return 0
}
