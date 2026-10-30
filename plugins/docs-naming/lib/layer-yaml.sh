#!/usr/bin/env bash
# layer-yaml.sh — read and write a docs-naming layer kept as YAML.
#
# Sourced by resolve-config.sh, setup-apply.sh and setup-check.sh, so the three
# agree on one conversion between the team file (`<home>/docs-naming.yaml`, its
# personal sibling `<home>/docs-naming.local.yaml`) and the JSON document the
# merge works on: `{"schema": 1, "file_names": {<key>: <value>}}`.
#
# THE FILE. Top-level keys are the `file_names` keys themselves, with no
# `schema` or `file_names` wrapper; plugins/docs-naming/schemas/docs-naming.schema.json
# validates it. Parsing is lib/yaml-subset.awk's, the repository's one YAML
# parser, so a value the parser rejects is a parse error here too. That parser
# reads every scalar as text, so the one key whose value is not text,
# `redirect_map: null`, is mapped back to JSON null, and an explicit empty list
# (`exempt_paths: []`, which the parser prints nothing for) is restored from the
# top-level line so "declared empty" stays different from "not declared".
#
# THE HOME. `<home>` is the convention home the repository binds in the pointer
# region of AGENTS.md or CLAUDE.md (lib/resolve-convention-home.sh), else
# docs/conventions.
#
# Needs jq and awk. Bash 3.2-compatible.

LAYER_YAML_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_YAML_AWK="$LAYER_YAML_LIB_DIR/yaml-subset.awk"
LAYER_YAML_HOME_RESOLVER="$LAYER_YAML_LIB_DIR/resolve-convention-home.sh"

# layer_yaml_home <root>: print the repo-relative convention home. A root that
# binds none, declined one, or binds a broken pointer gets the default.
layer_yaml_home() {
  local out
  if out="$(bash "$LAYER_YAML_HOME_RESOLVER" --root "$1" 2>/dev/null | tr -d '\r')" && [[ -n "$out" ]]; then
    printf '%s' "$out"
  else
    printf 'docs/conventions'
  fi
}

# layer_yaml_to_json <file>: print the layer as JSON on one line. Returns 1 with
# the parser's line and message on stderr when the file does not parse.
layer_yaml_to_json() {
  local file="$1" records empties
  [[ -f "$LAYER_YAML_AWK" ]] || {
    printf 'yaml parser missing at %s\n' "$LAYER_YAML_AWK" >&2
    return 1
  }
  if ! records="$(LC_ALL=C awk -f "$LAYER_YAML_AWK" <"$file" 2>/dev/null)"; then
    printf 'line %s\n' "$(printf '%s\n' "$records" | awk -F '\t' '$1 == "error" { print $2 ": " $3 }' | tail -n 1)" >&2
    return 1
  fi
  empties="$(LC_ALL=C tr -d '\r' <"$file" |
    sed -n 's/^\([A-Za-z0-9_-][A-Za-z0-9_-]*\)[[:space:]]*:[[:space:]]*\[[[:space:]]*\][[:space:]]*\(#.*\)\{0,1\}$/\1/p' |
    jq -R -s -c 'split("\n") | map(select(length > 0))')" || return 1
  printf '%s\n' "$records" | jq -R -s -c --argjson empties "$empties" '
    split("\n")
    | map(select(length > 0) | split("\t"))
    | map({p: .[0], v: (.[1:] | join("\t"))})
    | reduce .[] as $r (null;
        setpath(($r.p | split(".") | map(if test("^[0-9]+$") then tonumber else . end)); $r.v))
    | (. // {})
    | reduce $empties[] as $k (.; if has($k) then . else .[$k] = [] end)
    | del(."$schema")
    | if has("redirect_map") and .redirect_map == "null" then .redirect_map = null else . end
    | {schema: 1, file_names: .}
  ' | tr -d '\r'
}

# layer_yaml_render <file_names-json>: print the YAML body for a file_names
# object. Strings are double-quoted, which the subset parser reads back exactly
# for the characters a name, glob or command holds.
layer_yaml_render() {
  printf '%s' "$1" | jq -r '
    def pad($n): " " * $n;
    def sc: if type == "string" then tojson elif . == null then "null" else tostring end;
    def keyq: if test("^[A-Za-z0-9_-]+$") then . else tojson end;
    def render($ind):
      if type == "object" then
        to_entries[] | . as $e | ($e.key | keyq) as $k | $e.value as $v
        | if ($v | type) == "object" then
            (if ($v | length) == 0 then empty else (pad($ind) + $k + ":"), ($v | render($ind + 2)) end)
          elif ($v | type) == "array" then
            (if ($v | length) == 0 then pad($ind) + $k + ": []" else (pad($ind) + $k + ":"), ($v | render($ind + 2)) end)
          else pad($ind) + $k + ": " + ($v | sc) end
      elif type == "array" then
        .[] | if type == "object" then
                [render($ind + 2)] | to_entries[]
                | if .key == 0 then pad($ind) + "- " + (.value[($ind + 2):]) else .value end
              elif type == "array" then error("a nested sequence is outside the YAML subset")
              else pad($ind) + "- " + sc end
      else empty end;
    render(0)
  ' | tr -d '\r'
}
