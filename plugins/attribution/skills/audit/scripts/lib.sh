# shellcheck shell=bash
# Shared helpers for the /attribution:audit scripts (sourceable; not invoked
# directly).

# shellcheck source=../../../lib/config-root.sh
source "${BASH_SOURCE[0]%/*}/../../../lib/config-root.sh"

# require_opt_value <script> <option> [value ...]: refuse an option whose value
# is missing, empty, or another option. The script name is a parameter because
# each caller names itself in its own diagnostics; exit 2 is the usage code
# every caller documents in its own `Exit:` line.
require_opt_value() {
  local script="$1" opt="$2"
  if [[ $# -lt 3 || -z "${3:-}" || "$3" == -* ]]; then
    echo "$script: $opt requires a value" >&2
    exit 2
  fi
}

# json_str <text>: escape for a JSON string. Backslash and quote first, then the
# control characters a path, a reason, or a matched line can legally carry.
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

_CFG_LIB="${BASH_SOURCE[0]%/*}/../../../lib"

# cfg_layers_init <config-root>: fill CFG_LAYERS with the config cascade in
# refinement order, user-global then team then overlay, skipping a layer that is
# not present. The team layer is <home>/attribution.yaml and the overlay
# <home>/attribution.local.yaml (ADR 0075), <home> being the bound convention
# home, else docs/conventions. Each falls back to its .claude/attribution.json or
# .claude/attribution.local.json only when the YAML is absent: per file, not per
# key. The config root is a parameter because it is resolved differently per
# script (CLAUDE_PROJECT_DIR over a corpus root that each one finds its own way).
# Config-cascade step 2: a home or non-repo root has no team or overlay layer.
cfg_layers_init() {
  local config_root="$1" home="docs/conventions" resolved name layer
  CFG_LAYERS=()
  cfg_layer_add "${HOME:-/nonexistent}/.claude/attribution.json"
  [[ "$(config_root_classify "$config_root")" == repo ]] || return 0
  if resolved="$(bash "$_CFG_LIB/resolve-convention-home.sh" --root "$config_root" 2>/dev/null)" && [[ -n "$resolved" ]]; then
    home="$resolved"
  fi
  for name in attribution attribution.local; do
    layer="$config_root/$home/$name.yaml"
    [[ -f "$layer" ]] || layer="$config_root/.claude/$name.json"
    cfg_layer_add "$layer"
  done
}

# cfg_layer_add <path>: append <path> when present and not already a layer (two
# paths naming one file are read once). A YAML file outside the parser's subset
# is named on stderr and not a layer; the JSON it shadows stays unread.
cfg_layer_add() {
  local path="$1" layer
  [[ -f "$path" ]] || return 0
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    config_root_paths_same "$layer" "$path" && return 0
  done
  if _cfg_is_yaml "$path" && ! bash "$_CFG_LIB/parse-concern-value.sh" --strict "$path" __probe__ >/dev/null 2>&1; then
    echo "attribution: $path does not parse (quote a value that starts with *, & or !); its settings are not read" >&2
    return 0
  fi
  CFG_LAYERS+=("$path")
}

# The one reader every script takes its settings through. A layer is YAML (read
# with lib/parse-concern-value.sh, --strict, so a document outside the parser's
# subset is skipped whole) or legacy JSON (read with jq; without jq a JSON layer
# is skipped). Carriage returns are stripped because the Windows build of jq
# ends its lines with CRLF, and a CR-suffixed value silently stops matching (the
# ai-slop #3343 finding). CFG_SOURCE is the layer that supplied the value the
# last call returned, empty when none did, so --show-config can name it.
# shellcheck disable=SC2034  # read by the sourcing script
CFG_SOURCE=""

_cfg_is_yaml() { [[ "$1" == *.yaml || "$1" == *.yml ]]; }

# cfg_have_unread_layer: a JSON layer is present and jq is not there to read it.
cfg_have_unread_layer() {
  local layer
  command -v jq >/dev/null 2>&1 && return 1
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    _cfg_is_yaml "$layer" || return 0
  done
  return 1
}

# cfg_scalar <dest> <dotted-key> [<ere>]: the last layer whose value is non-empty
# (and, given <ere>, matches it) wins; a missing key, an empty value or a value
# that fails <ere> leaves the earlier value standing. <dest> is empty when no
# layer supplied one. The key is dotted (`gates.fix_precision_bar`).
cfg_scalar() {
  local -n _cfg_dest="$1"
  local _cfg_key="$2" _cfg_ere="${3:-}" _cfg_layer _cfg_v _cfg_out="" _cfg_src=""
  for _cfg_layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    if _cfg_is_yaml "$_cfg_layer"; then
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

# cfg_list <dest-array> <key>: the last layer that defines the top-level <key>
# replaces the list. Presence, not emptiness, decides: an explicit empty list is
# a value meaning "none", so an overlay can clear an earlier layer's list, while
# a layer that lacks the key leaves it standing. One element per line, internal
# spaces kept.
cfg_list() {
  local -n _cfg_arr="$1"
  local _cfg_key="$2" _cfg_layer _cfg_v _cfg_src="" _cfg_bom=$'\xEF\xBB\xBF'
  for _cfg_layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    if _cfg_is_yaml "$_cfg_layer"; then
      # The flattener prints nothing for `key: []`, so presence is the key's line
      # (after a byte-order mark, the key plain or quoted).
      grep -Eq "^(${_cfg_bom})?[\"']?${_cfg_key}[\"']?[[:space:]]*:" "$_cfg_layer" 2>/dev/null || continue
      _cfg_v="$(bash "$_CFG_LIB/parse-concern-value.sh" --strict --list "$_cfg_layer" "$_cfg_key" 2>/dev/null)" || continue
    else
      command -v jq >/dev/null 2>&1 || continue
      jq -e --arg k "$_cfg_key" 'has($k) and .[$k] != null' "$_cfg_layer" >/dev/null 2>&1 || continue
      # A value that is not a list (`false`, a string) clears the list.
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

# cfg_from_label <source>: how --show-config attributes one effective value.
cfg_from_label() {
  if [[ -z "$1" ]]; then
    printf '(bundled default)'
  else
    printf '(from %s)' "$1"
  fi
}

# cfg_layers_print: the layer listing every --show-config output opens with.
# Reads CFG_LAYERS, the same global the cfg_* readers take their layers from.
cfg_layers_print() {
  local layer
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
}
