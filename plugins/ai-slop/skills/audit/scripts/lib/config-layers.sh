# shellcheck shell=bash
# Which config-cascade layer files detect.sh reads, in order. Sourceable; not
# invoked directly. resolve_config_layers <repo-root> <show-config> sets
# CFG_LAYERS (the team file, then the personal layer) and OLD_PATH_NOTE (the
# warning about the old user-global file, or empty). It prints the warning to
# stderr unless <show-config> is 1, when the --show-config report prints it
# beside the layers instead.

_CONFIG_LAYERS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../lib" 2>/dev/null && pwd)"

# Config-cascade step 2: a home or non-repo root has no team layer or personal
# override, and a team file or personal override that is the user-global file is
# not read a second time.
# shellcheck source=../../../../lib/config-root.sh
source "$_CONFIG_LAYERS_LIB/config-root.sh"

resolve_config_layers() {
  local repo_root="$1" show_config="$2" old_user_cfg="${HOME:-/nonexistent}/.claude/ai-slop.json"
  local personal_cfg="" personal_present=0 conv_home home cfg
  CFG_LAYERS=()
  OLD_PATH_NOTE=""
  if [[ "$(config_root_classify "$repo_root")" == repo ]]; then
    # The team layer is <home>/ai-slop.yaml and the personal layer
    # <home>/ai-slop.local.yaml (ADR 0075).
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
