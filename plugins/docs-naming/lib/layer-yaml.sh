#!/usr/bin/env bash

LAYER_YAML_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_YAML_AWK="$LAYER_YAML_LIB_DIR/yaml-subset.awk"
LAYER_YAML_HOME_RESOLVER="$LAYER_YAML_LIB_DIR/resolve-convention-home.sh"

layer_yaml_home() {
  local out err rc
  err="$(mktemp)" || return 1
  out="$(bash "$LAYER_YAML_HOME_RESOLVER" --root "$1" 2>"$err")"
  rc=$?
  out="${out//$'\r'/}"
  case "$rc" in
  0) printf '%s' "$out" ;;
  1 | 4 | 5) printf 'docs/conventions' ;;
  *)
    printf 'convention home did not resolve (exit %s): %s\n' "$rc" "$(tr -d '\r' <"$err")" >&2
    rm -f "$err"
    return 1
    ;;
  esac
  rm -f "$err"
}

layer_yaml_to_json() {
  local file="$1" records empties declared blank
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
  declared="$(LC_ALL=C tr -d '\r' <"$file" | sed -n 's/^\([A-Za-z0-9_-][A-Za-z0-9_-]*\)[[:space:]]*:.*$/\1/p')"
  for blank in $declared; do
    grep -q "^${blank}[.	]" <<<"$records" && continue
    printf '%s' "$empties" | jq -e --arg k "$blank" 'index($k) != null' >/dev/null && continue
    printf 'line %s: empty value for "%s"; write a value or [], or remove the key\n' \
      "$(LC_ALL=C grep -n -E "^${blank}[[:space:]]*:" "$file" | head -n 1 | cut -d: -f1)" "$blank" >&2
    return 1
  done
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
