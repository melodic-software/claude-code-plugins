# shellcheck shell=bash

_CONFIG_LAYERS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../lib" 2>/dev/null && pwd)"

# shellcheck source=../../../../lib/config-root.sh
source "$_CONFIG_LAYERS_LIB/config-root.sh"

resolve_config_layers() {
  local repo_root="$1"
  local conv_home home cfg personal_cfg
  CFG_LAYERS=()
  if [[ "$(config_root_classify "$repo_root")" == repo ]]; then
    conv_home="docs/conventions"
    if home="$(bash "$_CONFIG_LAYERS_LIB/resolve-convention-home.sh" --root "$repo_root" 2>/dev/null)" && [[ -n "$home" ]]; then
      conv_home="$home"
    fi
    cfg="$repo_root/$conv_home/ai-slop.yaml"
    [[ -f "$cfg" ]] && CFG_LAYERS+=("$cfg")
    personal_cfg="$repo_root/$conv_home/ai-slop.local.yaml"
    [[ -f "$personal_cfg" ]] && CFG_LAYERS+=("$personal_cfg")
  fi
  return 0
}
