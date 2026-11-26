# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/hook-configs.sh is sourced-only\n' >&2
  exit 2
fi

# shellcheck source=manifest-path-guard.sh
. "$(dirname "${BASH_SOURCE[0]}")/manifest-path-guard.sh"

# US, not TAB: only a non-whitespace IFS keeps an empty field in its column:
# https://www.gnu.org/software/bash/manual/html_node/Word-Splitting.html
HOOK_CONFIGS_SEP=$'\x1f'

# shellcheck disable=SC2016  # jq source, never shell-expanded
HOOK_CONFIGS_JQ_DEFS='
  def render: map(if type == "number" then "[" + tostring + "]" else "." + . end) | join("");
  def flat: gsub("[\r\n\t\u001f]"; " ");
  def hook_rows($file; $doc; $prefix):
    ([[]] + [$doc | paths(objects)])[] as $p
    | ($doc | getpath($p)) as $o
    | select(($o | type) == "object")
    | select(($o.command | type) == "string")
    | ($o | has("args")) as $exec
    | ($exec and (($o.args | type) == "array")) as $array
    | ["H", $file, $prefix + ($p | render),
       (if $exec then "exec" else "shell" end),
       (if $array then "array" elif $exec then "other" else "none" end),
       $o.command,
       ([$o.command] + (if $array then $o.args | map(tostring) else [] end) | join(" "))]
    | map(flat) | join("\u001f");
'

# shellcheck disable=SC2016  # jq source, never shell-expanded
HOOK_CONFIGS_JQ_FILE="${HOOK_CONFIGS_JQ_DEFS}"'input_filename as $file | hook_rows($file; .; "")'

# $mode sources: I rows naming each inline map, P rows for each path.
# shellcheck disable=SC2016  # jq source, never shell-expanded
HOOK_CONFIGS_JQ_MANIFEST="${HOOK_CONFIGS_JQ_DEFS}"'
  input_filename as $file
  | def inline($doc; $at):
      if $mode == "rows" then hook_rows($file; $doc; $at | render)
      else ["I", $file, ($at | tojson)] | join("\u001f") end;
    def pointed($rel): ["P", $file, ($rel | flat)] | join("\u001f");
    .hooks as $h
    | if ($h | type) == "object" then inline($h; ["hooks"])
      elif ($h | type) == "string" then pointed($h)
      elif ($h | type) == "array" then
        $h | to_entries[]
        | if (.value | type) == "string" then pointed(.value)
          elif (.value | type) == "object" then inline(.value; ["hooks", .key])
          else empty end
      else empty end
'

EXEC_NAME_ALLOWLIST=(node)

hook_configs::allowed_exec_name() {
  local name
  for name in "${EXEC_NAME_ALLOWLIST[@]}"; do
    [[ "$1" == "$name" ]] && return 0
  done
  return 1
}

hook_configs::_need_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "$1: jq is required but not installed" >&2
    exit 2
  fi
}

hook_configs::_corpus() {
  local plugin
  _HC_HOOK_JSONS=()
  _HC_MANIFESTS=()
  for plugin in plugins/*/; do
    plugin="${plugin%/}"
    [[ -f "$plugin/hooks/hooks.json" ]] && _HC_HOOK_JSONS+=("$plugin/hooks/hooks.json")
    [[ -f "$plugin/.claude-plugin/plugin.json" ]] && _HC_MANIFESTS+=("$plugin/.claude-plugin/plugin.json")
  done
  return 0
}

hook_configs::_manifest_out() {
  local -n _hc_mo="$1"
  local _hc_mode="$2" _hc_bad="$3" _hc_one _hc_f
  shift 3
  _hc_mo=""
  (($#)) || return 0
  if _hc_mo="$(jq -r --arg mode "$_hc_mode" "$HOOK_CONFIGS_JQ_MANIFEST" "$@" 2>/dev/null)"; then
    _hc_mo="${_hc_mo//$'\r'/}"
    return 0
  fi
  _hc_mo=""
  for _hc_f in "$@"; do
    if _hc_one="$(jq -r --arg mode "$_hc_mode" "$HOOK_CONFIGS_JQ_MANIFEST" "$_hc_f" 2>/dev/null)"; then
      _hc_mo+="${_hc_one//$'\r'/}"$'\n'
    elif [[ -n "$_hc_bad" ]]; then
      "$_hc_bad" manifest "$_hc_f" "" "not parseable as JSON"
    fi
  done
  return 0
}

hook_configs::_pointed() {
  local -n _hc_seen="$2" _hc_into="$3"
  local _hc_manifest="$4" _hc_path
  manifest_path_guard::resolve_to _hc_path "$1" "$_hc_manifest" "${_hc_manifest%/.claude-plugin/plugin.json}" "$5"
  [[ -f "$_hc_path" && -z "${_hc_seen[$_hc_path]:-}" ]] || return 0
  _hc_seen["$_hc_path"]=1
  _hc_into+=("$_hc_path")
}

hook_configs::_scan_files() {
  local on_hook="$1" on_bad="$2" out f
  shift 2
  (($#)) || return 0
  if out="$(jq -r "$HOOK_CONFIGS_JQ_FILE" "$@" 2>/dev/null)"; then
    hook_configs::_dispatch "$on_hook" "$out"
    return 0
  fi
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    if out="$(jq -r "$HOOK_CONFIGS_JQ_FILE" "$f" 2>/dev/null)"; then
      hook_configs::_dispatch "$on_hook" "$out"
    else
      "$on_bad" json "$f" "" "not parseable as JSON"
    fi
  done
}

hook_configs::_dispatch() {
  local kind file where form args cmd argv
  while IFS="$HOOK_CONFIGS_SEP" read -r kind file where form args cmd argv; do
    [[ "$kind" == H ]] || continue
    "$1" "$file" "$where" "$form" "$args" "$cmd" "$argv"
  done <<<"${2//$'\r'/}"
}

hook_configs::_reader() {
  local pin candidate
  HOOK_CONFIGS_READER=()
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
      HOOK_CONFIGS_READER=("$candidate")
      return 0
    fi
  done
  pin="$(awk '/^pyyaml==/ { sub(/^pyyaml==/, ""); sub(/[[:space:]\\].*$/, ""); print; exit }' \
    .github/requirements-ci.txt 2>/dev/null || true)"
  if [[ -n "$pin" ]] && command -v uv >/dev/null 2>&1; then
    HOOK_CONFIGS_READER=(uv run --quiet --no-project --with "pyyaml==$pin" python)
    return 0
  fi
  {
    echo "$1: no python with PyYAML available, and no uv to borrow one."
    echo "PyYAML reads the skill/agent frontmatter surface; without it this gate"
    echo "would clear files it never parsed, so it stops instead. Either:"
    echo "  * install the pin: pip install 'pyyaml==${pin:-<see .github/requirements-ci.txt>}'"
    echo "  * or install uv, which this script will use without touching your python"
  } >&2
  exit 2
}

hook_configs::scan() {
  local gate="$1" on_hook="$2" on_bad="$3" out kind file rest line detail
  local -a pointed=()
  local -A seen=()
  hook_configs::_need_jq "$gate"
  hook_configs::_reader "$gate"
  hook_configs::_corpus
  for file in ${_HC_HOOK_JSONS[@]+"${_HC_HOOK_JSONS[@]}"}; do
    seen["$file"]=1
  done
  hook_configs::_scan_files "$on_hook" "$on_bad" ${_HC_HOOK_JSONS[@]+"${_HC_HOOK_JSONS[@]}"}

  hook_configs::_manifest_out out rows "$on_bad" ${_HC_MANIFESTS[@]+"${_HC_MANIFESTS[@]}"}
  hook_configs::_dispatch "$on_hook" "$out"
  while IFS="$HOOK_CONFIGS_SEP" read -r kind file rest; do
    [[ "$kind" == P ]] || continue
    hook_configs::_pointed "$gate" seen pointed "$file" "$rest"
  done <<<"$out"
  hook_configs::_scan_files "$on_hook" "$on_bad" ${pointed[@]+"${pointed[@]}"}

  if ! out="$("${HOOK_CONFIGS_READER[@]}" scripts/check-hook-exec-form-frontmatter.py plugins)"; then
    echo "$gate: the frontmatter reader did not complete; this gate cannot clear plugins/" >&2
    exit 2
  fi
  while IFS=$'\t' read -r kind file line detail; do
    detail="${detail%$'\r'}"
    case "$kind" in
    V) "$on_hook" "$file" "$line" exec array "$detail" "$detail" ;;
    N) "$on_hook" "$file" "$line" exec other "$detail" "$detail" ;;
    S) "$on_hook" "$file" "$line" shell none "$detail" "$detail" ;;
    X) "$on_bad" frontmatter "$file" "$line" "$detail" ;;
    *) ;;
    esac
  done <<<"$out"
  return 0
}

hook_configs::sources() {
  local gate="$1" out kind file rest
  local -a pointed=()
  local -A seen=()
  hook_configs::_need_jq "$gate"
  hook_configs::_corpus
  HOOK_CONFIG_SOURCES=()
  for file in ${_HC_HOOK_JSONS[@]+"${_HC_HOOK_JSONS[@]}"}; do
    # shellcheck disable=SC2034  # read by hook_configs::_pointed through a nameref
    seen["$file"]=1
    HOOK_CONFIG_SOURCES+=("$file"$'\t''["hooks"]')
  done
  hook_configs::_manifest_out out sources "" ${_HC_MANIFESTS[@]+"${_HC_MANIFESTS[@]}"}
  while IFS="$HOOK_CONFIGS_SEP" read -r kind file rest; do
    case "$kind" in
    I) HOOK_CONFIG_SOURCES+=("$file"$'\t'"$rest") ;;
    P) hook_configs::_pointed "$gate" seen pointed "$file" "$rest" ;;
    *) ;;
    esac
  done <<<"$out"
  for file in ${pointed[@]+"${pointed[@]}"}; do
    HOOK_CONFIG_SOURCES+=("$file"$'\t''["hooks"]')
  done
  return 0
}
