# shellcheck shell=bash
# Shared helpers for the /attribution:audit scripts (sourceable; not invoked
# directly).

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

# cfg_layers_init <config-root>: fill CFG_LAYERS with the .claude/attribution.json
# cascade in refinement order, user-global then team then overlay, skipping a
# layer that is not present. The config root is a parameter because it is
# resolved differently per script (CLAUDE_PROJECT_DIR over a corpus root that
# each one finds its own way).
cfg_layers_init() {
  local config_root="$1"
  CFG_LAYERS=()
  cfg_layer_add "${HOME:-/nonexistent}/.claude" attribution.json
  cfg_layer_add "$config_root/.claude" attribution.json
  cfg_layer_add "$config_root/.claude" attribution.local.json
}

# cfg_layer_add <dir> <name>: append <dir>/<name> when present. A layer holding
# only the legacy provenance file name is never read; it draws one warning.
cfg_layer_add() {
  local dir="$1" name="$2" legacy="$1/provenance${2#attribution}"
  if [[ -f "$dir/$name" ]]; then
    CFG_LAYERS+=("$dir/$name")
  elif [[ -f "$legacy" ]]; then
    echo "warning: legacy config $legacy is not read; rename it to $dir/$name" >&2
  fi
  return 0
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
