# shellcheck shell=bash

_CFG_LIB="${BASH_SOURCE[0]%/*}/../../../lib"

# shellcheck source=../../../lib/config-root.sh
source "$_CFG_LIB/config-root.sh"
# shellcheck source=../../../lib/opt-value.sh
source "$_CFG_LIB/opt-value.sh"

json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

CFG_USER_CONFIG_KEYS=(budgets.searches_per_candidate budgets.fetches_per_candidate
  budgets.corpus_fetch_ceiling judge_samples accuracy.nomination_passes
  accuracy.judge_lens_diversity accuracy.review_agents accuracy.deep_research_on_exhaustion)
declare -A CFG_USER_CONFIG=()

cfg_user_config() {
  local key="${1%%=*}" value="${1#*=}" known
  [[ "$1" == *=* ]] || return 1
  for known in "${CFG_USER_CONFIG_KEYS[@]}"; do
    [[ "$key" == "$known" ]] || continue
    [[ -z "$value" || "$value" == *"\${user_config."* ]] || CFG_USER_CONFIG["$key"]="$value"
    return 0
  done
  return 1
}

cfg_layers_init() {
  local config_root="$1" home="docs/conventions" resolved name moved_to="this plugin's userConfig (see How to set these in the attribution README) for budgets, judge_samples and accuracy, and"
  local repo_files="a repository's <home>/attribution.yaml or attribution.local.yaml"
  local old="${HOME:-/nonexistent}/.claude/attribution.json"
  CFG_LAYERS=()
  cfg_layer_add "$old"
  [[ "${#CFG_USER_CONFIG[@]}" -eq 0 ]] || CFG_LAYERS+=(userConfig)
  if [[ "$(config_root_classify "$config_root")" == repo ]]; then
    if resolved="$(bash "$_CFG_LIB/resolve-convention-home.sh" --root "$config_root" 2>/dev/null)" && [[ -n "$resolved" ]]; then
      home="$resolved"
    fi
    for name in attribution attribution.local; do
      cfg_layer_add "$config_root/$home/$name.yaml"
    done
    repo_files="$config_root/$home/attribution.yaml or attribution.local.yaml"
  fi
  [[ -f "$old" ]] || return 0
  echo "attribution: $old is a retired location, still read below every other layer until it is moved; run /attribution:setup apply to move its settings to $moved_to $repo_files for every other key" >&2
}

cfg_layer_add() {
  local path="$1" layer
  [[ -f "$path" ]] || return 0
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    [[ "$layer" != userConfig ]] || continue
    config_root_paths_same "$layer" "$path" && return 0
  done
  if _cfg_is_yaml "$path" && ! bash "$_CFG_LIB/parse-concern-value.sh" --strict "$path" __probe__ >/dev/null 2>&1; then
    echo "attribution: $path does not parse (quote a value that starts with *, & or !); its settings are not read" >&2
    return 0
  fi
  CFG_LAYERS+=("$path")
}

# shellcheck disable=SC2034  # read by the sourcing script
CFG_SOURCE=""

_cfg_is_yaml() { [[ "$1" == *.yaml || "$1" == *.yml ]]; }

cfg_have_unread_layer() {
  local layer
  command -v jq >/dev/null 2>&1 && return 1
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    _cfg_is_yaml "$layer" || [[ "$layer" == userConfig ]] || return 0
  done
  return 1
}

cfg_scalar() {
  local -n _cfg_dest="$1"
  local _cfg_key="$2" _cfg_ere="${3:-}" _cfg_layer _cfg_v _cfg_out="" _cfg_src=""
  for _cfg_layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    if [[ "$_cfg_layer" == userConfig ]]; then
      _cfg_v="${CFG_USER_CONFIG[$_cfg_key]-}"
    elif _cfg_is_yaml "$_cfg_layer"; then
      _cfg_v="$(bash "$_CFG_LIB/parse-concern-value.sh" --strict "$_cfg_layer" "$_cfg_key" 2>/dev/null)" || continue
    else
      command -v jq >/dev/null 2>&1 || continue
      _cfg_v="$(jq -r --arg k "$_cfg_key" 'getpath($k | split(".")) // empty' "$_cfg_layer" 2>/dev/null)" || continue
    fi
    _cfg_v="${_cfg_v//$'\r'/}"
    [[ -n "$_cfg_v" ]] || continue
    [[ -z "$_cfg_ere" || "$_cfg_v" =~ $_cfg_ere ]] || continue
    _cfg_out="$_cfg_v"
    _cfg_src="$_cfg_layer"
  done
  CFG_SOURCE="$_cfg_src"
  # shellcheck disable=SC2034  # nameref: writes the caller's variable
  _cfg_dest="$_cfg_out"
}

cfg_list() {
  local -n _cfg_arr="$1"
  local _cfg_key="$2" _cfg_layer _cfg_v _cfg_src="" _cfg_bom=$'\xEF\xBB\xBF'
  for _cfg_layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    [[ "$_cfg_layer" != userConfig ]] || continue
    if _cfg_is_yaml "$_cfg_layer"; then
      grep -Eq "^(${_cfg_bom})?[\"']?${_cfg_key}[\"']?[[:space:]]*:" "$_cfg_layer" 2>/dev/null || continue
      _cfg_v="$(bash "$_CFG_LIB/parse-concern-value.sh" --strict --list "$_cfg_layer" "$_cfg_key" 2>/dev/null)" || continue
    else
      command -v jq >/dev/null 2>&1 || continue
      jq -e --arg k "$_cfg_key" 'has($k) and .[$k] != null' "$_cfg_layer" >/dev/null 2>&1 || continue
      _cfg_v="$(jq -r --arg k "$_cfg_key" '(.[$k] // []) | .[]' "$_cfg_layer" 2>/dev/null)" || _cfg_v=""
    fi
    _cfg_v="${_cfg_v//$'\r'/}"
    _cfg_src="$_cfg_layer"
    if [[ -n "${_cfg_v//[[:space:]]/}" ]]; then
      mapfile -t _cfg_arr <<<"$_cfg_v"
    else
      # shellcheck disable=SC2034  # nameref: clears the caller's array
      _cfg_arr=()
    fi
  done
  # shellcheck disable=SC2034  # read by the sourcing script
  CFG_SOURCE="$_cfg_src"
}

cfg_from_label() {
  if [[ -z "$1" ]]; then
    printf '(bundled default)'
  else
    printf '(from %s)' "$1"
  fi
}

cfg_layers_print() {
  local layer
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
}
