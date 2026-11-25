#!/usr/bin/env bash
# Exit codes:
#   0  inventory COMPLETE — every enabled plugin resolved to a real directory
#   1  inventory PARTIAL  — at least one enabled plugin could not be resolved or
#      read. The audit keeps the conditional-finding posture for the families
#      those plugins might cover. Not an error; a stated limit.
#   2  fatal — jq missing, or no settings scope readable at all

set -uo pipefail

jqs() { jq "$@" 2>/dev/null | tr -d '\r'; }

jqn() { MSYS2_ARG_CONV_EXCL='*' jq -cn "$@" | tr -d '\r'; }

json_nodes() {
  local w="$1" prog="$2"
  shift 2
  [[ $# -gt 0 ]] || return 0
  printf '%s\0' "$@" | base64 | tr -d '\r\n' |
    jq -R -c --argjson w "$w" "@base64d | split(\"\\u0000\")[:-1] | range(0; length; \$w) as \$i | .[\$i : \$i + \$w] as \$f | $prog" |
    tr -d '\r'
}

print_array() {
  local name="$1" sep="" n nodes=()
  shift
  mapfile -t nodes < <(json_nodes "$@")
  printf '  "%s": [' "$name"
  for n in ${nodes+"${nodes[@]}"}; do
    printf '%s\n    %s\n' "$sep" "$n"
    sep=","
  done
  printf '\n  ]'
}

usage() {
  cat <<'EOF'
check-hook-coverage.sh — enumerate the hooks actually installed for this project.

Reads settings-declared hooks (project, local, user scope) and plugin-declared
hooks (from the marketplace directory a directory-source marketplace loads,
else via the installed-plugin registry), plus the levers that suppress hooks
wholesale. When a plugin resolves both ways to different directories, the pair
is reported as an info note. Read-only; never runs a hook.

Usage:
  check-hook-coverage.sh [--json] [--help]

  --json   emit the inventory as JSON on stdout instead of a table
           (project_root, hooks, plugins, divergence, levers, unreadable)

Exit: 0 inventory complete; 1 inventory partial (some plugin unresolved);
      2 fatal (jq missing, or no settings scope readable).
EOF
}

EMIT_JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --json)
    EMIT_JSON=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi


PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

RESOLVE_SCOPES_LIB="$PLUGIN_ROOT/lib/resolve-scopes.sh"
if [[ ! -r "$RESOLVE_SCOPES_LIB" ]]; then
  echo "ERROR: cannot read $RESOLVE_SCOPES_LIB; the plugin's shared scope-resolution library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/resolve-scopes.sh
# shellcheck disable=SC1091
source "$RESOLVE_SCOPES_LIB"

PROJECT_ROOT=""
scopes::project_root_to PROJECT_ROOT "${HOOK_COVERAGE_FIXTURE_DIR:-}"
USER_DIR=""
scopes::user_dir_to USER_DIR "${HOOK_COVERAGE_USER_DIR:-}"
INSTALLED_JSON=""
scopes::installed_registry_to INSTALLED_JSON "${HOOK_COVERAGE_INSTALLED_JSON:-}" "$USER_DIR"

SCOPES=()
SCOPE_LABELS=()
add_scope() {
  [[ -f "$1" ]] || return 0
  if ! jq empty "$1" 2>/dev/null; then
    UNREADABLE+=("$2 ($1): not valid JSON")
    PARTIAL=1
    LEVER_STATE=unknown
    return 0
  fi
  SCOPES+=("$1")
  SCOPE_LABELS+=("$2")
}

PARTIAL=0
UNREADABLE=()
LEVER_STATE=complete
declare -A BAD_CATALOG=()

add_scope "$PROJECT_ROOT/.claude/settings.json" "project"
add_scope "$PROJECT_ROOT/.claude/settings.local.json" "local"
[[ -n "$USER_DIR" ]] && add_scope "$USER_DIR/settings.json" "user"

MANAGED_SCOPE_LIB="$PLUGIN_ROOT/lib/managed-scope.sh"
MANAGED_NOTE=""
MANAGED_PRESENT=false
if [[ -r "$MANAGED_SCOPE_LIB" ]]; then
  # shellcheck source=../../../lib/managed-scope.sh
  # shellcheck disable=SC1091
  source "$MANAGED_SCOPE_LIB"
  MANAGED_FILE="$(mscope::base_file "${HOOK_COVERAGE_MANAGED_JSON:-}")"
  if [[ -f "$MANAGED_FILE" ]]; then
    MANAGED_PRESENT=true
    add_scope "$MANAGED_FILE" "managed"
  else
    MANAGED_NOTE="Managed-settings JSON not present at ${MANAGED_FILE}; registry/plist managed policy is not read."
  fi
  compgen -G "$(mscope::dropin_dir "${HOOK_COVERAGE_MANAGED_JSON:-}")/*.json" >/dev/null && MANAGED_PRESENT=true
else
  MANAGED_NOTE="Managed-scope library missing; managed hook-suppression levers were not read."
fi

if [[ ${#SCOPES[@]} -eq 0 ]]; then
  echo "ERROR: no readable settings scope found (looked under $PROJECT_ROOT/.claude and ${USER_DIR:-<no user dir>})" >&2
  for u in ${UNREADABLE+"${UNREADABLE[@]}"}; do echo "  unreadable: $u" >&2; done
  exit 2
fi


# shellcheck disable=SC2016  # a jq program: $h/$event/$matcher are jq variables and must reach jq unexpanded
HOOK_ROWS_JQ='
  def flat: tostring | gsub("[\t\r\n]"; " ");
  (.hooks // {}) as $h
  | [ $h | to_entries[]
      | .key as $event
      | (.value // [])
      | if type == "array" then . else [] end
      | .[]
      | ((.matcher // "*") | if . == "" then "*" else . end) as $matcher
      | ((.hooks // []) | if type == "array" then . else [] end)[]
      | [ ($event | flat),
          ($matcher | flat),
          ((.command // .url // "<no command>") | if . == "" then "<no command>" else . end | flat),
          ({ timeout: (if (.timeout | type) == "number" then .timeout else null end),
             type: ((.type // "command") | tostring),
             if: ((.if // "") | tostring),
             shell: ((.shell // "") | tostring),
             args: (.args // [])
           } | tojson)
        ]
    ]
  | .[] | join("\t")
'

PLUGIN_HOOK_NORMALIZE_JQ='if has("hooks") then . else {hooks: .} end'

ROWS=()
emit_rows() {
  local src="$1" input="$2" mode="${3:-file}" out
  if [[ "$mode" == "--inline" ]]; then
    out="$(printf '%s' "$input" | jqs -r "$PLUGIN_HOOK_NORMALIZE_JQ | $HOOK_ROWS_JQ")"
  else
    out="$(jqs -r "$HOOK_ROWS_JQ" "$input")"
  fi
  add_rows "$src" $? "$out"
}

add_rows() {
  local src="$1" rc="$2" out="$3" line
  if [[ $rc -ne 0 ]]; then
    UNREADABLE+=("$src: hook config did not parse")
    PARTIAL=1
    return 0
  fi
  [[ -z "$out" ]] && return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] && ROWS+=("$src	$line")
  done <<<"$out"
}

for i in "${!SCOPES[@]}"; do
  emit_rows "settings:${SCOPE_LABELS[$i]}" "${SCOPES[$i]}"
done


LEVERS=()
for i in "${!SCOPES[@]}"; do
  # shellcheck disable=SC2016  # a jq program; $s and $k are jq variables
  while IFS=$'\t' read -r key val; do
    [[ -n "$val" ]] && LEVERS+=("${SCOPE_LABELS[$i]}	$key	$val")
  done < <(jqs -j '. as $s | ["disableAllHooks", "allowManagedHooksOnly", "strictPluginOnlyCustomization"][]
    | select(. as $k | $s | has($k)) | . + "\t" + ($s[.] | tojson) + "\n"' "${SCOPES[$i]}")
done


MOD_PLANE=()
# shellcheck disable=SC2016  # a jq program; $k is a jq variable
MOD_PLANE_JQ='
  def obj: if type == "object" then . else {} end;
  (obj as $s | ["prependPlugins", "appendPlugins", "disableSideloadFlags"][] as $k
    | select($s | has($k)) | [$k, ($s[$k] | tojson)]),
  (obj | .pluginConfigs | obj | .["cc-plugin-sec-default@builtin"] | obj | .options | obj
    | to_entries[] | select(.key == "allowManagedModsOnly" or .key == "allowModsToOverrideDenyRules")
    | [.key, (.value | tojson)])
  | @tsv'
for i in "${!SCOPES[@]}"; do
  while IFS=$'\t' read -r mk mv; do
    [[ -n "$mk" ]] && MOD_PLANE+=("${SCOPE_LABELS[$i]}	$mk	$mv")
  done < <(jqs -r "$MOD_PLANE_JQ" "${SCOPES[$i]}")
done


declare -A ENABLED_STATE=()
merge_enabled_plugins() {
  local label="$1" i
  for i in "${!SCOPE_LABELS[@]}"; do
    if [[ "${SCOPE_LABELS[$i]}" == "$label" ]]; then
      while IFS=$'\t' read -r pk pv; do
        [[ -z "$pk" ]] && continue
        ENABLED_STATE[$pk]="$pv"
      done < <(jqs -r '(.enabledPlugins // {}) | to_entries[] | [.key, (.value | tostring)] | @tsv' "${SCOPES[$i]}")
      return 0
    fi
  done
}
for label in user project local; do
  merge_enabled_plugins "$label"
done
ENABLED=()
for pk in "${!ENABLED_STATE[@]}"; do
  [[ "${ENABLED_STATE[$pk]}" == "true" ]] && ENABLED+=("$pk")
done

PLUGIN_STATUS=()


NUL_FIELDS=()
nul_fields() {
  local x opt
  NUL_FIELDS=()
  for opt in -d --decode -D; do
    if base64 "$opt" <<<"$1" >"$FIELDS_FILE" 2>/dev/null; then
      while IFS= read -r -d '' x; do NUL_FIELDS+=("$x"); done <"$FIELDS_FILE"
      return 0
    fi
  done
  return 1
}
FIELDS_FILE="$(mktemp 2>/dev/null)" || {
  echo "ERROR: could not create a temp file" >&2
  exit 2
}
trap 'rm -f "$FIELDS_FILE"' EXIT

declare -A INSTALL_PATH=()
if [[ -f "$INSTALLED_JSON" && ${#ENABLED[@]} -gt 0 ]]; then
  project_norm="${PROJECT_ROOT//\\//}"
  project_norm="${project_norm%/}"
  # shellcheck disable=SC2016  # $project is a jq --arg binding, not a shell variable
  if nul_fields "$(jqs -r --arg project "$project_norm" '
    def rank($s): if $s == "local" then 3 elif $s == "project" then 2 elif $s == "user" then 1 else 0 end;
    . as $reg
    | [$ARGS.positional[] as $k
      | ($reg.plugins // {})[$k] // []
      | if type == "array" then . else [] end
      | map(select(.installPath != null))
      | map(. + {scope: (.scope // "user"), projectPath: ((.projectPath // "") | gsub("\\\\"; "/") | rtrimstr("/"))})
      | map(select(
          .projectPath == "" or .projectPath == $project
          or (.projectPath as $pp | $project | startswith($pp + "/"))
        ))
      | sort_by(-(rank(.scope)))
      | (.[0].installPath // empty | tostring | gsub("\r"; "")) as $p
      | $k, $p]
    | map(gsub("\u0000"; "") + "\u0000") | add // "" | @base64
  ' "$INSTALLED_JSON" --args "${ENABLED[@]}")"; then
    for ((n = 0; n + 1 < ${#NUL_FIELDS[@]}; n += 2)); do
      INSTALL_PATH["${NUL_FIELDS[n]}"]="${NUL_FIELDS[n + 1]}"
    done
  fi
fi

norm_path_to() {
  local _np="${2//\\//}"
  while [[ "$_np" == */ && ${#_np} -gt 1 ]]; do _np="${_np%/}"; done
  while [[ "$_np" == *$'\n' ]]; do _np="${_np%$'\n'}"; done
  printf -v "$1" '%s' "$_np"
}

join_path_to() {
  local _base _p
  norm_path_to _base "$2"
  norm_path_to _p "$3"
  while [[ "$_p" == ./* ]]; do _p="${_p#./}"; done
  if [[ "$_p" == /* || "$_p" =~ ^[A-Za-z]:(/|$) ]]; then
    printf -v "$1" '%s' "$_p"
  elif [[ -z "$_p" || "$_p" == "." ]]; then
    printf -v "$1" '%s' "$_base"
  else
    printf -v "$1" '%s' "$_base/$_p"
  fi
}

canon_dir_to() {
  local _here="$PWD"
  if cd -P -- "$2" 2>/dev/null; then
    printf -v "$1" '%s' "$PWD"
    cd -- "$_here" || exit 2
  else
    printf -v "$1" '%s' "$2"
  fi
}

resolve_marketplace_dir_to() {
  local _name="$2" label i base rel known
  for label in project local user; do
    for i in "${!SCOPE_LABELS[@]}"; do
      [[ "${SCOPE_LABELS[$i]}" == "$label" ]] || continue
      # shellcheck disable=SC2016  # $n is a jq --arg binding, not a shell variable
      rel="$(jqs -r --arg n "$_name" '
        ((.extraKnownMarketplaces // {})[$n] // {})
        | (.source // {})
        | select(type == "object" and .source == "directory")
        | .path // empty | tostring
      ' "${SCOPES[$i]}")"
      [[ -n "$rel" ]] || continue
      if [[ "$label" == "user" ]]; then base="$(dirname "$USER_DIR")"; else base="$PROJECT_ROOT"; fi
      join_path_to "$1" "$base" "$rel"
      return 0
    done
  done
  [[ -n "$USER_DIR" ]] || return 1
  known="$USER_DIR/plugins/known_marketplaces.json"
  [[ -f "$known" ]] || return 1
  # shellcheck disable=SC2016  # $n is a jq --arg binding, not a shell variable
  rel="$(jqs -r --arg n "$_name" '
    (.[$n] // {})
    | select(type == "object" and ((.source // {}) | type) == "object" and (.source // {}).source == "directory")
    | .installLocation // empty | tostring
  ' "$known")"
  [[ -n "$rel" ]] || return 1
  norm_path_to "$1" "$rel"
}

US=$'\x1f'
declare -A MKT_STATE=() MKT_DIR=() MKT_SRC=()
load_marketplace() {
  local mkt="$1" mdir="" catalog n
  MKT_STATE[$mkt]=none
  resolve_marketplace_dir_to mdir "$mkt" || return 0
  [[ -n "$mdir" ]] || return 0
  catalog="$mdir/.claude-plugin/marketplace.json"
  [[ -f "$catalog" ]] || return 0
  if ! tr -d '\r' <"$catalog" | jq empty 2>/dev/null; then
    MKT_STATE[$mkt]=bad
    return 0
  fi
  MKT_DIR[$mkt]="$mdir"
  MKT_STATE[$mkt]=ok
  # shellcheck disable=SC2016  # $e is a jq binding, not a shell variable
  nul_fields "$(jqs -r '
    (.plugins // []) | if type == "array" then . else [] end
    | reduce (.[] | select(type == "object" and (.name | type) == "string")) as $e
        ({}; if has($e.name) then . else .[$e.name] = $e.source end)
    | [to_entries[] | select(.value | type == "string") | .key, (.value | gsub("\r"; ""))]
    | map(gsub("\u0000"; "") + "\u0000") | add // "" | @base64
  ' "$catalog")" || return 0
  for ((n = 0; n + 1 < ${#NUL_FIELDS[@]}; n += 2)); do
    MKT_SRC["$mkt$US${NUL_FIELDS[n]}"]="${NUL_FIELDS[n + 1]}"
  done
}

marketplace_plugin_path_to() {
  local _key="$2" _plugin _mkt _dir
  printf -v "$1" '%s' ""
  [[ "$_key" == *@* ]] || return 1
  _plugin="${_key%@*}"
  _mkt="${_key##*@}"
  [[ -n "${MKT_STATE[$_mkt]+x}" ]] || load_marketplace "$_mkt"
  case "${MKT_STATE[$_mkt]}" in
  bad) return 2 ;;
  ok) ;;
  *) return 1 ;;
  esac
  [[ -n "${MKT_SRC["$_mkt$US$_plugin"]:-}" ]] || return 1
  join_path_to _dir "${MKT_DIR[$_mkt]}" "${MKT_SRC["$_mkt$US$_plugin"]}"
  [[ -d "$_dir" ]] || return 1
  printf -v "$1" '%s' "$_dir"
}

DIVERGENCE=()
REGISTRY_FALLBACKS=0

for key in ${ENABLED+"${ENABLED[@]}"}; do
  marketplace_plugin_path_to mpath "$key"
  mrc=$?
  if [[ $mrc -eq 2 ]]; then
    bad_mkt="${key##*@}"
    if [[ -z "${BAD_CATALOG[$bad_mkt]:-}" ]]; then
      BAD_CATALOG[$bad_mkt]=1
      UNREADABLE+=("marketplace:$bad_mkt: its .claude-plugin/marketplace.json is not valid JSON; plugins it lists resolve through the registry cache instead")
      PARTIAL=1
    fi
  fi
  norm_path_to rpath "${INSTALL_PATH[$key]:-}"
  loaded_note=""
  if [[ -n "$mpath" ]]; then
    path="$mpath"
    loaded_note=" (loaded from marketplace directory)"
    if [[ -n "$rpath" ]]; then
      mcanon="" rcanon=""
      canon_dir_to mcanon "$mpath"
      canon_dir_to rcanon "$rpath"
      [[ "$mcanon" != "$rcanon" ]] && DIVERGENCE+=("$key	$mpath	$rpath")
    fi
  else
    REGISTRY_FALLBACKS=$((REGISTRY_FALLBACKS + 1))
    path="$rpath"
    if [[ -z "$path" ]]; then
      PLUGIN_STATUS+=("$key	UNRESOLVED	no installPath in the installed-plugin registry	")
      PARTIAL=1
      continue
    fi
    if [[ ! -d "$path" ]]; then
      PLUGIN_STATUS+=("$key	UNRESOLVED	registry names $path, which is not a directory	")
      PARTIAL=1
      continue
    fi
  fi

  manifest="$path/.claude-plugin/plugin.json"
  declared=""
  if [[ -f "$manifest" ]]; then
    declared="$(jqs -r 'if has("hooks") then (.hooks | tostring) else empty end' "$manifest")"
  fi

  before=${#ROWS[@]}
  found=0

  if [[ -n "$declared" ]]; then
    htype="$(jqs -r '.hooks | type' "$manifest")"
    case "$htype" in
    string | array)
      while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        rel="${rel#./}"
        if [[ -f "$path/$rel" ]]; then
          emit_rows "plugin:$key" "$path/$rel"
          found=1
        else
          UNREADABLE+=("plugin:$key declares hooks at $rel, which does not exist")
          PARTIAL=1
        fi
      done < <(jqs -r 'if (.hooks | type) == "array" then .hooks[] else .hooks end' "$manifest")
      ;;
    object)
      emit_rows "plugin:$key" "$declared" --inline
      found=1
      ;;
    *)
      UNREADABLE+=("plugin:$key declares a hooks key of unsupported type $htype")
      PARTIAL=1
      ;;
    esac
  fi

  if [[ $found -eq 0 && -f "$path/hooks/hooks.json" ]]; then
    if jq empty "$path/hooks/hooks.json" 2>/dev/null; then
      out="$(jqs -r "(try ($PLUGIN_HOOK_NORMALIZE_JQ) catch empty) | $HOOK_ROWS_JQ" "$path/hooks/hooks.json")"
      add_rows "plugin:$key" $? "$out"
      found=1
    else
      UNREADABLE+=("plugin:$key: hooks/hooks.json is not valid JSON")
      PARTIAL=1
    fi
  fi

  added=$((${#ROWS[@]} - before))
  if [[ $found -eq 0 ]]; then
    PLUGIN_STATUS+=("$key	NO-HOOKS	no hooks/hooks.json and no hooks key in plugin.json$loaded_note	$path")
  else
    PLUGIN_STATUS+=("$key	OK	$added hook command(s)$loaded_note	$path")
  fi
done

if [[ $REGISTRY_FALLBACKS -gt 0 && ! -f "$INSTALLED_JSON" ]]; then
  UNREADABLE+=("installed_plugins.json not found at ${INSTALLED_JSON:-<unset>}; $REGISTRY_FALLBACKS enabled plugin(s) outside a marketplace directory could not be enumerated")
  PARTIAL=1
fi


# Each single-quoted string below is a jq program run through jqn; its $names are jq bindings.
# shellcheck disable=SC2016
if [[ $EMIT_JSON -eq 1 ]]; then
  {
    printf '{\n'
    printf '  "inventory": "%s",\n' "$([[ $PARTIAL -eq 0 ]] && echo complete || echo partial)"
    printf '  "lever_state": "%s",\n' "$LEVER_STATE"
    printf '  "managed_scope": %s,\n' "$MANAGED_PRESENT"
    printf '  "project_root": %s,\n' "$(jqn --arg r "$PROJECT_ROOT" '$r')"
    fields=()
    for r in ${ROWS+"${ROWS[@]}"}; do
      IFS=$'\t' read -r src event matcher cmd extra <<<"$r"
      fields+=("$src" "$event" "$matcher" "$cmd" "${extra:-{\}}")
    done
    print_array hooks 5 '{source: $f[0], event: $f[1], matcher: $f[2], command: $f[3]} + ($f[4] | fromjson)' ${fields+"${fields[@]}"}
    printf ',\n'
    fields=()
    for p in ${PLUGIN_STATUS+"${PLUGIN_STATUS[@]}"}; do
      IFS=$'\t' read -r pk st note ppath <<<"$p"
      fields+=("$pk" "$st" "$note" "${ppath:-}")
    done
    print_array plugins 4 '{plugin: $f[0], status: $f[1], note: $f[2], path: $f[3]}' ${fields+"${fields[@]}"}
    printf ',\n'
    fields=()
    for d in ${DIVERGENCE+"${DIVERGENCE[@]}"}; do
      IFS=$'\t' read -r dk dl dc <<<"$d"
      fields+=("$dk" "$dl" "$dc")
    done
    print_array divergence 3 '{plugin: $f[0], loaded: $f[1], cached: $f[2]}' ${fields+"${fields[@]}"}
    printf ',\n'
    fields=()
    for l in ${LEVERS+"${LEVERS[@]}"}; do
      IFS=$'\t' read -r sc lk lv <<<"$l"
      fields+=("$sc" "$lk" "$lv")
    done
    print_array levers 3 '($f[2] | try fromjson catch null) as $v
      | {scope: $f[0], key: $f[1], value: (if $v == null or $v == false then $f[2] else $v end)}' ${fields+"${fields[@]}"}
    printf ',\n'
    fields=()
    for l in ${MOD_PLANE+"${MOD_PLANE[@]}"}; do
      IFS=$'\t' read -r sc mk mv <<<"$l"
      fields+=("$sc" "$mk" "$mv")
    done
    print_array mod_plane 3 '{scope: $f[0], key: $f[1], value: ($f[2] | fromjson)}' ${fields+"${fields[@]}"}
    printf ',\n'
    print_array unreadable 1 '$f[0]' ${UNREADABLE+"${UNREADABLE[@]}"}
    printf '\n}\n'
  }
else
  echo "Hook inventory"
  echo "=============="
  echo "Project root: $PROJECT_ROOT"
  echo "Scopes read:  ${SCOPE_LABELS[*]}"
  echo "Registry:     ${INSTALLED_JSON:-<none>}"
  echo
  if [[ ${#ROWS[@]} -eq 0 ]]; then
    echo "Hooks: none found in any enumerated source."
  else
    echo "Hooks (${#ROWS[@]}):"
    printf '  %-28s %-22s %-12s %s\n' "SOURCE" "EVENT" "MATCHER" "COMMAND"
    for r in "${ROWS[@]}"; do
      IFS=$'\t' read -r src event matcher cmd _extra <<<"$r"
      printf '  %-28s %-22s %-12s %s\n' "$src" "$event" "$matcher" "$cmd"
    done
  fi
  echo
  if [[ ${#PLUGIN_STATUS[@]} -gt 0 ]]; then
    echo "Enabled plugins (${#PLUGIN_STATUS[@]}):"
    for p in "${PLUGIN_STATUS[@]}"; do
      IFS=$'\t' read -r pk st note _ppath <<<"$p"
      printf '  %-8s %-40s %s\n' "$st" "$pk" "$note"
    done
    echo
  fi
  if [[ ${#DIVERGENCE[@]} -gt 0 ]]; then
    echo "Cache-versus-loaded divergence (${#DIVERGENCE[@]}):"
    for d in "${DIVERGENCE[@]}"; do
      IFS=$'\t' read -r dk dl dc <<<"$d"
      printf '  %s: loads %s; registry cache at %s\n' "$dk" "$dl" "$dc"
    done
    echo "  Info: the session loads the marketplace directory; the cache is what a tool resolving through the registry would read."
    echo
  fi
  if [[ "$LEVER_STATE" != "complete" ]]; then
    echo "Hook-suppression lever state: UNKNOWN — a settings scope did not parse, so a lever that switches hooks off may be set and unread."
    echo
  fi
  if [[ ${#LEVERS[@]} -gt 0 ]]; then
    echo "Hook-suppression levers set:"
    for l in "${LEVERS[@]}"; do
      IFS=$'\t' read -r sc lk lv <<<"$l"
      printf '  %-8s %-32s %s\n' "$sc" "$lk" "$lv"
    done
    echo
  fi
  if [[ ${#MOD_PLANE[@]} -gt 0 ]]; then
    echo "Mod-plane keys set:"
    for l in "${MOD_PLANE[@]}"; do
      IFS=$'\t' read -r sc mk mv <<<"$l"
      printf '  %-8s %-32s %s\n' "$sc" "$mk" "$mv"
    done
    echo
  fi
  if [[ ${#UNREADABLE[@]} -gt 0 ]]; then
    echo "Not enumerated (${#UNREADABLE[@]}) — treat the families these might cover as unsettled:"
    for u in "${UNREADABLE[@]}"; do echo "  - $u"; done
    echo
  fi
  if [[ $PARTIAL -eq 0 ]]; then
    echo "INVENTORY: complete — every enabled plugin resolved and every hook source parsed in the scopes read (${SCOPE_LABELS[*]})."
    [[ -n "$MANAGED_NOTE" ]] && echo "  Managed caveat: $MANAGED_NOTE"
  else
    echo "INVENTORY: partial — see 'Not enumerated' above. Narrowing 3 stays conditional for anything those sources could cover."
  fi
fi

exit $PARTIAL
