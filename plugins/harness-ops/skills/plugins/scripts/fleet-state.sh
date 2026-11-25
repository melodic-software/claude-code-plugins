#!/usr/bin/env bash
# Exit codes:
#   0  ran to completion (individual marketplace failures are reported in the
#      JSON body, not the exit code, so an --all sweep with partial failures
#      still exits 0)
#   1  a single-marketplace run's marketplace could not be resolved/read
#   2  fatal: jq missing, an internal CC state file is present but does not
#      match its expected shape (fail loud on schema drift — never guess), a
#      bad/absent --ids selector, --ids combined with --all, or a rejected
#      --from invocation (see the --from paragraph above)

set -uo pipefail

script_src="${BASH_SOURCE[0]}"
case "$script_src" in
*/*) script_src_dir="${script_src%/*}" ;;
*) script_src_dir="." ;;
esac
PLUGIN_ROOT_DEFAULT=""
if builtin pushd "$script_src_dir/../../.." >/dev/null 2>&1; then
  PLUGIN_ROOT_DEFAULT="$PWD"
  builtin popd >/dev/null 2>&1 || true
fi

HOOK_UTILS="$PLUGIN_ROOT_DEFAULT/hooks/hook-utils.sh"
if [[ -f "$HOOK_UTILS" ]]; then
  # shellcheck source=/dev/null
  builtin source "$HOOK_UTILS"
else
  echo "ERROR: hook-utils.sh not found at $HOOK_UTILS" >&2
  exit 2
fi

JQ_CAPTURE="$script_src_dir/jq-capture.sh"
if [[ -f "$JQ_CAPTURE" ]]; then
  # shellcheck source=jq-capture.sh
  builtin source "$JQ_CAPTURE"
else
  echo "ERROR: jq-capture.sh not found at $JQ_CAPTURE" >&2
  exit 2
fi

INSTALLED_JSON="${FLEET_STATE_INSTALLED_JSON:-$HOME/.claude/plugins/installed_plugins.json}"
MARKETPLACES_JSON="${FLEET_STATE_MARKETPLACES_JSON:-$HOME/.claude/plugins/known_marketplaces.json}"
USER_SETTINGS="${FLEET_STATE_USER_SETTINGS:-$HOME/.claude/settings.json}"

case_insensitive_os="false"
case "${OSTYPE:-}" in
msys* | cygwin* | win32) case_insensitive_os="true" ;;
*) ;;
esac

native_cwd_to() {
  local __nc_dir="$2" __nc_v=""
  if [[ "$case_insensitive_os" == "true" && "$__nc_dir" =~ ^/([a-zA-Z])(/.*)?$ ]]; then
    __nc_v="${BASH_REMATCH[1]^}:${BASH_REMATCH[2]:-/}"
  else
    __nc_v=$(builtin cd "$__nc_dir" 2>/dev/null && { builtin pwd -W 2>/dev/null || builtin pwd; }) || __nc_v=""
  fi
  [[ -n "$__nc_v" ]] || __nc_v="$__nc_dir"
  printf -v "$1" '%s' "$__nc_v"
}

usage() {
  local text
  IFS= read -r -d '' text <<'EOF' || true
fleet-state.sh: read-only plugin-fleet state, as one JSON object or a plain id list.

Usage:
  fleet-state.sh [--marketplace <name> | --all]
  fleet-state.sh [--marketplace <name>] --ids <selector>
  fleet-state.sh --ids <selector> --from <report.json> [--marketplace <name>]
  fleet-state.sh --marketplaces

With neither --marketplace nor --all, the target is the marketplace this plugin
was installed from. --ids prints one TAB-separated record per line instead of
JSON; the first field is the <name>@<marketplace> id. --from projects --ids from
a saved single-marketplace report instead of reading the fleet. --marketplaces
prints every marketplace name, one per line.

Selectors: installed-user, update-candidates-user, update-candidates-project,
downgrade-candidates, current-project, missing-user-install, missing-enabled,
user-scope-orphans.

Exit: 0 ran to completion; 1 a single marketplace could not be resolved;
2 usage error, jq missing, or a state file that does not match its expected shape.

The output shapes are in context/script-contracts.md and context/scope-semantics.md.
EOF
  printf '%s\n' "$text"
}

MODE="default"
TARGET=""
IDS_SELECTOR=""
LIST_MARKETPLACES=""
FROM_REPORT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplaces)
    LIST_MARKETPLACES="yes"
    shift
    ;;
  --ids)
    IDS_SELECTOR="${2:-}"
    if [[ -z "$IDS_SELECTOR" ]]; then
      echo "ERROR: --ids requires a selector" >&2
      exit 2
    fi
    shift 2
    ;;
  --from)
    FROM_REPORT="${2:-}"
    if [[ -z "$FROM_REPORT" ]]; then
      echo "ERROR: --from requires a report path" >&2
      exit 2
    fi
    shift 2
    ;;
  --marketplace)
    MODE="single"
    TARGET="${2:-}"
    if [[ -z "$TARGET" ]]; then
      echo "ERROR: --marketplace requires a name" >&2
      exit 2
    fi
    shift 2
    ;;
  --all)
    MODE="all"
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument: $1 (see --help)" >&2
    exit 2
    ;;
  esac
done

if [[ -n "$LIST_MARKETPLACES" ]]; then
  if [[ "$MODE" != "default" || -n "$IDS_SELECTOR" || -n "$FROM_REPORT" ]]; then
    echo "ERROR: --marketplaces cannot be combined with --marketplace, --all, --ids, or --from" >&2
    exit 2
  fi
  MODE="list"
fi

if [[ -n "$IDS_SELECTOR" && "$MODE" == "all" ]]; then
  echo "ERROR: --ids cannot be combined with --all" >&2
  echo "  Run --ids once per marketplace with --marketplace <name>." >&2
  exit 2
fi

ids_selector_valid() {
  case "$1" in
  installed-user | update-candidates-user | update-candidates-project | downgrade-candidates | current-project | missing-user-install | missing-enabled | user-scope-orphans)
    return 0
    ;;
  *)
    echo "ERROR: unknown --ids selector: $1" >&2
    echo "  expected one of: installed-user, update-candidates-user," >&2
    echo "                   update-candidates-project, downgrade-candidates," >&2
    echo "                   current-project, missing-user-install," >&2
    echo "                   missing-enabled, user-scope-orphans" >&2
    return 1
    ;;
  esac
}

ids_selector_required_fields() {
  case "$1" in
  installed-user | current-project) echo 'installed:array' ;;
  update-candidates-user | update-candidates-project | downgrade-candidates)
    echo 'installed:array catalog_versions:object'
    ;;
  missing-user-install) echo 'missing_from_user_install:array' ;;
  missing-enabled) echo 'missing_from_enabled:array' ;;
  user-scope-orphans) echo 'user_scope_orphans:array' ;;
  *) echo '' ;;
  esac
}

if [[ -n "$IDS_SELECTOR" ]]; then
  ids_selector_valid "$IDS_SELECTOR" || exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

VERSION_TRIPLE_DEF='
  def version_triple:
    if type == "string" then
      ((capture("^v?(?<maj>[0-9]+)[.](?<min>[0-9]+)[.](?<pat>[0-9]+)") // null)
       | if . == null then null else [.maj, .min, .pat] | map(tonumber) end)
    else null end;'

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PROJECTION_PROGRAM='
  def proven_downgrade($iv; $cv):
    ($iv | version_triple) as $i | ($cv | version_triple) as $c
    | ($i != null and $c != null and $c < $i);
  if $selector == "" then $block
    elif $selector == "installed-user" then ($block.installed[]? | select(.scope == "user") | .id)
    elif $selector == "update-candidates-user" then
      ($block.catalog_versions as $cvs | ($block.delisted // []) as $delisted
       | $block.installed[]? | select(.scope == "user")
       | .id as $id
       | select((($cvs[$id]) == null or ($cvs[$id]) != .version)
                and (proven_downgrade(.version; $cvs[$id]) | not)
                and ($delisted | index($id) | not))
       | $id)
    elif $selector == "update-candidates-project" then
      ($block.catalog_versions as $cvs | ([($block.delisted_project // [])[].id]) as $delisted
       | $block.installed[]? | select(.currentProject == true)
       | .id as $id
       | select((proven_downgrade(.version; $cvs[$id]) | not)
                and ($delisted | index($id) | not))
       | "\(.id)\t\(.scope)")
    elif $selector == "downgrade-candidates" then
      ($block.catalog_versions as $cvs | $block.installed[]?
       | select(.scope == "user" or .currentProject == true)
       | select(proven_downgrade(.version; $cvs[.id]))
       | "\(.id)\t\(.scope)\t\(.version)\t\($cvs[.id])")
    elif $selector == "current-project" then ($block.installed[]? | select(.currentProject == true) | "\(.id)\t\(.scope)")
    elif $selector == "missing-user-install" then $block.missing_from_user_install[]?
    elif $selector == "missing-enabled" then $block.missing_from_enabled[]?
    elif $selector == "user-scope-orphans" then $block.user_scope_orphans[]?
    else error("unknown selector: " + $selector) end'

FS_FROM_NAME=""
if [[ -n "$FROM_REPORT" ]]; then
  if [[ "$MODE" == "all" ]]; then
    echo "ERROR: --from cannot be combined with --all" >&2
    echo "  --from projects ONE saved single-marketplace report." >&2
    exit 2
  fi
  if [[ -z "$IDS_SELECTOR" ]]; then
    echo "ERROR: --from requires --ids <selector>" >&2
    echo "  --from projects a selector from a saved report; it emits no JSON report itself." >&2
    exit 2
  fi
  if [[ ! -f "$FROM_REPORT" ]]; then
    echo "ERROR: --from report not found: $FROM_REPORT" >&2
    exit 2
  fi
  FS_FROM_CHECK=""
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  if ! jq_to FS_FROM_CHECK -r --arg required "$(ids_selector_required_fields "$IDS_SELECTOR")" '
        if type != "object" then "err:not a JSON object"
        elif has("marketplaces") then "err:this is an --all envelope, not a single-marketplace report"
        elif (.marketplace | type) != "object" or (.marketplace.name | type) != "string"
          then "err:missing or wrong-typed field .marketplace.name (expected a string)"
        elif (.installed | type) != "array"
          then "err:missing or wrong-typed field .installed (expected an array)"
        else . as $r
          | [$required | split(" ")[] | select(length > 0) | split(":")
             | select(($r[.[0]] | type) != .[1])
             | "missing or wrong-typed field .\(.[0]) (expected \(if .[1] == "array" then "an" else "a" end) \(.[1]))"]
            as $bad
          | if ($bad | length) > 0 then "err:" + ($bad | join("; "))
            else "ok:" + $r.marketplace.name end
        end' "$FROM_REPORT" 2>/dev/null; then
    FS_FROM_CHECK="err:not valid JSON"
  fi
  if [[ "$FS_FROM_CHECK" != ok:* ]]; then
    echo "ERROR: --from report is not a usable fleet-state report for --ids $IDS_SELECTOR: $FROM_REPORT" >&2
    echo "  ${FS_FROM_CHECK#err:}" >&2
    echo "  Expected the JSON object \`--marketplace <name>\` prints (.marketplace.name," >&2
    echo "  .installed, .catalog_versions, …), not an --all envelope or arbitrary JSON." >&2
    exit 2
  fi
  FS_FROM_NAME="${FS_FROM_CHECK#ok:}"
  if [[ "$MODE" == "single" && "$TARGET" != "$FS_FROM_NAME" ]]; then
    echo "ERROR: --from report is for marketplace '$FS_FROM_NAME', not '$TARGET': $FROM_REPORT" >&2
    exit 2
  fi
  if ! jq_to FS_BLOCK -r --arg selector "$IDS_SELECTOR" \
    "$VERSION_TRIPLE_DEF . as \$block | $PROJECTION_PROGRAM" "$FROM_REPORT"; then
    echo "ERROR: --from projection failed for selector '$IDS_SELECTOR': $FROM_REPORT" >&2
    exit 2
  fi
  [[ -n "$FS_BLOCK" ]] && printf '%s\n' "$FS_BLOCK"
  exit 0
fi

FS_READ_SET=()
read_set() { [[ -z "${FLEET_STATE_READ_LIST:-}" ]] || FS_READ_SET+=("$@"); }
[[ -z "${FLEET_STATE_READ_LIST:-}" ]] ||
  trap 'printf "%s\n" ${FS_READ_SET[@]+"${FS_READ_SET[@]}"} >"$FLEET_STATE_READ_LIST"' EXIT
read_set "$INSTALLED_JSON" "$MARKETPLACES_JSON" "$USER_SETTINGS"

if [[ ! -f "$INSTALLED_JSON" ]]; then
  echo "ERROR: installed_plugins.json not found: $INSTALLED_JSON" >&2
  exit 2
fi
if [[ ! -f "$MARKETPLACES_JSON" ]]; then
  echo "ERROR: known_marketplaces.json not found: $MARKETPLACES_JSON" >&2
  exit 2
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$PROJECT_ROOT" && "$MODE" != "list" ]]; then
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT=""
  PROJECT_ROOT="${PROJECT_ROOT//$'\r'/}"
fi

cwd_native=""
home_native=""
phys_tmp=""
cwd_norm=""
home_norm=""
key_json=""
plugin_root="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT_DEFAULT}"
prime_paths=()
[[ -n "$PROJECT_ROOT" || "$MODE" == "list" ]] || read_set "$PWD/.claude"
if [[ -z "$PROJECT_ROOT" && "$MODE" != "list" && -d "$PWD/.claude" ]]; then
  native_cwd_to cwd_native "$PWD"
  [[ -z "${HOME:-}" ]] || read_set "$HOME"
  if [[ -n "${HOME:-}" && -d "$HOME" ]]; then
    native_cwd_to home_native "$HOME"
  fi
  prime_paths+=("$cwd_native")
  [[ -n "$home_native" ]] && prime_paths+=("$home_native")
fi
[[ -n "$PROJECT_ROOT" ]] && prime_paths+=("$PROJECT_ROOT")
[[ "$MODE" == "default" ]] && prime_paths+=("$plugin_root")
if ((${#prime_paths[@]} > 0)); then
  hook::_physical_prime "${prime_paths[@]}"
fi

if [[ -n "$cwd_native" ]]; then
  if [[ -n "$home_native" ]]; then
    hook::_physical_cached_to phys_tmp "$home_native" || true
    hook::normalize_path_to home_norm "$phys_tmp"
  fi
  hook::_physical_cached_to phys_tmp "$cwd_native" || true
  hook::normalize_path_to cwd_norm "$phys_tmp"
  [[ "$cwd_norm" != "$home_norm" ]] && PROJECT_ROOT="$cwd_native"
fi

current_project_norm=""
if [[ -n "$PROJECT_ROOT" ]]; then
  hook::_physical_cached_to phys_tmp "$PROJECT_ROOT" || true
  hook::normalize_path_to current_project_norm "$phys_tmp"
  current_project_norm="${current_project_norm%/}"
fi

norm_root=""
norm_root_parent=""
phys_root=""
if [[ "$MODE" == "default" ]]; then
  hook::_physical_cached_to phys_tmp "$plugin_root" || true
  phys_root="$phys_tmp"
  hook::normalize_path_to norm_root "$phys_tmp"
  norm_root="${norm_root%/}"
  norm_root_parent="${norm_root%/*}"
  [[ -n "$norm_root_parent" && "$norm_root_parent" != "$norm_root" ]] || norm_root_parent=""
fi

settings_args=()
[[ -f "$USER_SETTINGS" ]] && settings_args+=(--rawfile us "$USER_SETTINGS")
if [[ -n "$PROJECT_ROOT" ]]; then
  read_set "$PROJECT_ROOT/.claude/settings.json" "$PROJECT_ROOT/.claude/settings.local.json"
  [[ -f "$PROJECT_ROOT/.claude/settings.json" ]] &&
    settings_args+=(--rawfile ps "$PROJECT_ROOT/.claude/settings.json")
  [[ -f "$PROJECT_ROOT/.claude/settings.local.json" ]] &&
    settings_args+=(--rawfile ls "$PROJECT_ROOT/.claude/settings.local.json")
fi

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PASS1_PROGRAM='
  def parsed($raw): ($raw | try (fromjson | {ok: .}) catch {err: true});
  def map_of($raw; $label):
    if $raw == null then {}
    else (parsed($raw) | if .err then error("ERR\u001f" + $label + " is not valid JSON")
          else (.ok | .enabledPlugins // {}) end)
    end;
  (parsed($inst_raw) | if .err then {err: ("installed_plugins.json is not valid JSON: " + $inst_path)}
     elif (.ok | type == "object" and has("plugins") and (.plugins | type == "object")
           and (.plugins | to_entries | all(.value | type == "array"))) | not
     then {err: ("installed_plugins.json does not match the expected {plugins: {<id>: [...]}} shape: " + $inst_path)}
     else . end) as $ip
  | (parsed($mk_raw) | if .err then {err: ("known_marketplaces.json is not valid JSON: " + $mk_path)}
     elif (.ok | type) != "object" then {err: ("known_marketplaces.json is not a JSON object: " + $mk_path)}
     else . end) as $mp
  | if $ip.err then "ERR\u001f" + $ip.err
    elif $mp.err then "ERR\u001f" + $mp.err
    else
      $ip.ok as $inst | $mp.ok as $mk
      | map_of($ARGS.named.us; "user settings") as $u
      | map_of($ARGS.named.ps; "project settings") as $p
      | map_of($ARGS.named.ls; "local settings") as $l
      | ("CTX\u001f" + ({
            known_ids: (($u + $p + $l) | keys),
            effective: ($u + $p + $l),
            false_ids: ([($u, $p, $l) | to_entries[] | select(.value == false) | .key] | unique)
          } | tojson)),
        ($mk | keys[] as $k
          | ("NAME\u001f" + $k),
            (if $mk[$k] then ($mk[$k]
              | "MP\u001f\($k)\u001f\(.installLocation // "")\u001f\((.autoUpdate // false) | tostring)\u001f\(.lastUpdated // "")\u001f\(
                  # The source flattened to one line for the report: a string
                  # source as-is, an object source as `<kind>:<locator>`.
                  .source
                  | if type == "string" then .
                    elif type == "object" then ([(.source // empty), (.repo // .url // .path // empty)] | map(tostring) | join(":"))
                    else "" end
                  | gsub("[\n\r\t]"; " "))")
             else empty end)),
        ([$inst.plugins | to_entries[] | .value[] | select(.scope == "project" or .scope == "local") | .projectPath // empty]
          | unique | .[] | "PP\u001f\(.)"),
        (if $mode == "default" then
           ($ci == "true") as $cib
           | ([$inst.plugins | to_entries[]
               | select(.value[] | (.installPath // "" | gsub("\\\\"; "/")) as $p |
                        if $cib then ($p | ascii_downcase) == ($root | ascii_downcase) else $p == $root end)
               | .key] | .[0] // "") as $exact
           | (if $exact != "" then $exact
              elif $parent == "" then ""
              else ([$inst.plugins | to_entries[]
                     | select(.value[] | (.installPath // "" | gsub("\\\\"; "/") | rtrimstr("/") | sub("/[^/]*$"; "")) as $pp |
                              if $cib then ($pp | ascii_downcase) == ($parent | ascii_downcase) else $pp == $parent end)
                     | .key] | .[0] // "")
              end) as $hit
           | "TARGET" + ([31] | implode) + ($hit | sub(".*@"; "")),
           # Stage 3b, emitted unconditionally so the shell can consult it only
           # after stage 3a has had its turn. The value is already a bare
           # known_marketplaces.json key, so it gets NO `sub(".*@"; "")`.
           (if $root == "" then "" else
              ([$mk | to_entries[] | select(.value)
                | ((.value.installLocation // "") | gsub("\\\\"; "/") | rtrimstr("/")) as $loc
                | select($loc != "")
                | select(if $cib
                         then ($root | ascii_downcase) == ($loc | ascii_downcase)
                              or (($root | ascii_downcase) | startswith(($loc | ascii_downcase) + "/"))
                         else $root == $loc or ($root | startswith($loc + "/")) end)
                | .key] | .[0] // "")
            end) as $lochit
           | "LOCHIT" + ([31] | implode) + $lochit
         else empty end)
    end'

pass1=""
if ! jq_to pass1 -rn \
  --rawfile inst_raw "$INSTALLED_JSON" --arg inst_path "$INSTALLED_JSON" \
  --rawfile mk_raw "$MARKETPLACES_JSON" --arg mk_path "$MARKETPLACES_JSON" \
  --arg mode "$MODE" --arg root "$norm_root" --arg parent "$norm_root_parent" --arg ci "$case_insensitive_os" \
  ${settings_args[@]+"${settings_args[@]}"} \
  "$PASS1_PROGRAM"; then
  echo "ERROR: could not read the enabledPlugins scopes (see the jq error above)" >&2
  exit 2
fi

ctx_json=""
mp_names=()
mp_keys=()
mp_loc=()
mp_au=()
mp_lu=()
mp_src=()
pp_lines=()
resolved_target=""
location_target=""
while IFS=$'\x1f' read -r tag f1 f2 f3 f4 f5; do
  case "$tag" in
  ERR)
    echo "ERROR: $f1" >&2
    exit 2
    ;;
  CTX) ctx_json="$f1" ;;
  NAME) mp_names+=("$f1") ;;
  MP)
    mp_keys+=("$f1")
    mp_loc+=("$f2")
    mp_au+=("$f3")
    mp_lu+=("$f4")
    mp_src+=("$f5")
    ;;
  PP) pp_lines+=("$f1") ;;
  TARGET) resolved_target="$f1" ;;
  LOCHIT) location_target="$f1" ;;
  *) ;;
  esac
done <<<"$pass1"

if [[ "$MODE" == "list" ]]; then
  for n in ${mp_names[@]+"${mp_names[@]}"}; do
    printf '%s\n' "$n"
  done
  exit 0
fi

presence_tsv=""
settings_bundle=""
for pp in ${pp_lines[@]+"${pp_lines[@]}"}; do
  [[ -n "$pp" ]] || continue
  pp_fs="${pp//\\//}"
  read_set "$pp_fs"
  if [[ -d "$pp_fs" ]]; then
    read_set "$pp_fs/.git" "$pp_fs/.claude/settings.json"
    pp_linked="false"
    if [[ -f "$pp_fs/.git" ]]; then
      pp_gitfile=""
      IFS= read -r pp_gitfile <"$pp_fs/.git" || true
      pp_gitfile="${pp_gitfile//$'\r'/}"
      pp_gitfile="${pp_gitfile//\\//}"
      case "$pp_gitfile" in
      gitdir:*/worktrees/*/modules/*) ;;
      gitdir:*/worktrees/*)
        pp_gd="${pp_gitfile#gitdir:}"
        pp_gd="${pp_gd# }"
        case "$pp_gd" in
        /* | ?:/*) ;;
        *) pp_gd="$pp_fs/$pp_gd" ;;
        esac
        read_set "$pp_gd/commondir"
        [[ -f "$pp_gd/commondir" ]] && pp_linked="true"
        ;;
      *) ;;
      esac
    fi
    presence_tsv+="$pp"$'\t'"true"$'\t'"$pp_linked"$'\n'
    pp_settings="M"
    if [[ -f "$pp_fs/.claude/settings.json" ]]; then
      pp_settings=""
      IFS= read -r -d '' pp_settings <"$pp_fs/.claude/settings.json" || true
      pp_settings="F$pp_settings"
      [[ "$pp_settings" != *[$'\x1c'-$'\x1f']* ]] || pp_settings="U"
    fi
    [[ "$pp" != *[$'\x1c'-$'\x1f']* ]] && settings_bundle+="$pp"$'\x1e'"$pp_settings"$'\x1f'
  else
    presence_tsv+="$pp"$'\t'"false"$'\n'
  fi
done

FS_BLOCK=""

error_block_to() {
  local __eb_name __eb_err __eb_lu
  json_string_to __eb_name "$2"
  json_string_to __eb_err "$3"
  if [[ $# -ge 5 ]]; then
    json_string_to __eb_lu "$5"
    printf -v "$1" '{"marketplace":{"name":%s,"autoUpdate":%s,"lastUpdated":%s,"error":%s}}' \
      "$__eb_name" "$4" "$__eb_lu" "$__eb_err"
  else
    printf -v "$1" '{"marketplace":{"name":%s,"error":%s}}' "$__eb_name" "$__eb_err"
  fi
}

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PASS2_PROGRAM='
  ($c | try (fromjson | {ok: .}) catch {err: true})
  | if .err then "INVALID"
    else "OK", (.ok | .plugins[]? | select((.source | type) == "string") | "E\u001f\(.name)\u001f\(.source)")
    end'

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
PASS3_PROGRAM="$VERSION_TRIPLE_DEF"'
  (. | split("\u001d")) as $parts
  | ($parts[0] | fromjson) as $ctx
  | ($parts[1] | split("\n")
      | map(select(length > 0) | split("\t") | select(length >= 2 and (.[0] | length) > 0)
            | {key: .[0], value: (.[1] == "true")})
      | from_entries) as $pres
  # Third column: whether a PRESENT path is a linked git worktree. Absent from a
  # path that is not present, so the lookup below answers null, never false.
  | ($parts[1] | split("\n")
      | map(select(length > 0) | split("\t") | select(length >= 3 and (.[0] | length) > 0))
      | map({key: .[0], value: (.[2] == "true")})
      | from_entries) as $wt
  # The settings file of each present path, parsed once: {state: "absent"} for no
  # file, {state: "unreadable"} for one that does not parse or whose
  # enabledPlugins is not an object, else {state: "ok", map}.
  | ($parts[3] // "" | split("\u001f")
      | map(select(length > 0) | split("\u001e") | select(length >= 2 and (.[0] | length) > 0)
            | {key: .[0],
               value: (.[1] as $t
                 | if ($t | startswith("M")) then {state: "absent"}
                   elif ($t | startswith("U")) then {state: "unreadable"}
                   else (($t[1:] | try fromjson catch null) as $j
                         | if ($j | type) != "object" then {state: "unreadable"}
                           elif ($j.enabledPlugins // {} | type) != "object" then {state: "unreadable"}
                           else {state: "ok", map: ($j.enabledPlugins // {})} end) end)})
      | from_entries) as $pset
  # Entries whose source is not a string never reached the payload, so they
  # are absent from this map entirely — a lookup returns null, the same
  # fail-open answer as an entry whose manifest could not be read. A manifest
  # that does not parse, carries no version, or carries false yields null too;
  # every value this collapses lands on the FAIL-OPEN side, so the collapse
  # cannot cause a wrong withhold. A numeric 0 is preserved.
  | ($parts[2] | split("\u001f")
      | map(select(length > 0) | split("\u001e") | select(length >= 2 and (.[0] | length) > 0)
            | {key: (.[0] + "@" + $name),
               value: (.[1]
                 | if . == "" then null else (try (fromjson | .version) catch null) end
                 | if . == null or . == false then null elif type == "string" then . else tojson end)})
      | from_entries) as $cv
  | ($ci == "true") as $cib
  | ($home | gsub("\\\\"; "/") | sub("/+$"; "")) as $home_n
  # Every install record for ids in this marketplace, flattened, with the
  # currentProject flag Windows-normalized on both sides.
  | ($inst[0].plugins | to_entries
      | map(select(.key | endswith("@" + $name))
            | .key as $id
            | .value[]
            | {
                id: $id,
                scope: .scope,
                version: .version,
                # The record'"'"'s cache directory, as recorded: the one place a
                # consumer can read the installed build'"'"'s own manifest from.
                installPath: (.installPath // null),
                projectPath: (.projectPath // null),
                currentProject: (
                  if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 and ($cur | length) > 0 then
                    (.projectPath | gsub("\\\\"; "/")) as $p |
                    if $cib then ($p | ascii_downcase) == ($cur | ascii_downcase) else $p == $cur end
                  else null end
                ),
                projectPathPresent: (
                  if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 then
                    # `has` rather than `$pres[$pp] // null`: jq treats FALSE as
                    # empty for `//`, so the alternative operator would silently
                    # rewrite a genuine "not present" into "not checked".
                    .projectPath as $pp
                    | (if ($pres | has($pp)) then $pres[$pp] else null end)
                  else null end
                ),
                projectPathIsHome: (
                  if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 then
                    (.projectPath | gsub("\\\\"; "/") | sub("/+$"; "")) as $p
                    | ($p | test("^/home/[^/]+$"))
                      or ($p | test("^(/Users/[^/]+|/mnt/[a-z]/Users/[^/]+|[a-z]:/Users/[^/]+)$"; "i"))
                      or ($home_n != "" and $home_n != "/"
                          and (if $cib then ($p | ascii_downcase) == ($home_n | ascii_downcase) else $p == $home_n end))
                  else null end
                ),
                linkedWorktree: (
                  if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 then
                    .projectPath as $pp
                    | (if ($wt | has($pp)) then $wt[$pp] else null end)
                  else null end
                ),
                # The raw enabledPlugins entry for this id in the present path'"'"'s
                # .claude/settings.json: "true", "false", "other" (a value that is
                # not a boolean), "absent" (no file, no map, or no key), or
                # "unreadable"; null when the path is not present or the record is
                # user scope. `claude plugin list` reports no entry and an explicit
                # false alike, so this is what tells them apart.
                projectEnabledEntry: (
                  if (.scope == "project" or .scope == "local") and (.projectPath // "" | length) > 0 then
                    .projectPath as $pp
                    | (if ($pset | has($pp)) then $pset[$pp] else null end) as $ps
                    | if $ps == null then null
                      elif $ps.state != "ok" then $ps.state
                      elif ($ps.map | has($id)) | not then "absent"
                      elif $ps.map[$id] == true then "true"
                      elif $ps.map[$id] == false then "false"
                      else "other" end
                  else null end
                )
              })) as $installed
  # A lagging project/local record in a linked worktree: `claude plugin update`
  # reports success there and leaves the record unchanged (#6713), so the record
  # is labeled instead of dropped. It stays in installed[] and in divergences[],
  # and the label never changes versionsMatch. "Lagging" is measured against the
  # catalog version when it parses, else the highest version any record of the id
  # holds; a version that does not parse is never labeled.
  | ($installed | group_by(.id)
      | map({key: .[0].id, value: ([.[].version | version_triple | select(. != null)] | max)})
      | from_entries) as $highest
  | ($installed | map(
      . as $r
      | (($cv[$r.id] | version_triple) // $highest[$r.id]) as $ref
      | $r + {label: (
          if $r.linkedWorktree == true and ($r.version | version_triple) != null
             and $ref != null and ($r.version | version_triple) < $ref
          then "update ineffective, uninstall clears it" else null end)}
    )) as $installed
  | ([$catalog[0].plugins[]?.name // empty] | unique) as $catalog_names
  | ($catalog_names | map(. + "@" + $name)) as $catalog_ids
  | ([$installed[].id] | unique) as $installed_ids
  # catalog minus installed minus any id explicitly opted out (false) in any
  # scope, even one never installed at all.
  | (($catalog_ids - $installed_ids) - $ctx.false_ids) as $missing_from_install
  # User-scope completeness, distinct from all-scope missing_from_install: a
  # plugin installed only at project/local scope is present all-scope but not
  # usable from other directories, so `sync` Step 4 (which installs at user
  # scope for the "usable from any directory" guarantee) must key off this.
  | ([$installed[] | select(.scope == "user") | .id] | unique) as $user_installed_ids
  | (($catalog_ids - $user_installed_ids) - $ctx.false_ids) as $missing_from_user_install
  # Ids with a project/local record and NO user-scope record. Deliberately NOT
  # filtered to catalog membership: an installed id the catalog no longer
  # carries is exactly the kind of record a reader wants named. An opt-out is
  # an answer, not a gap, so those are subtracted like the two arrays above.
  | (((([$installed[] | select(.scope == "project" or .scope == "local") | .id] | unique)
       - ([$installed[] | select(.scope == "user") | .id] | unique))
      - $ctx.false_ids)) as $user_scope_orphans
  | ($ctx.known_ids | map(select(endswith("@" + $name)))) as $known_at_mp
  # missing_from_enabled can only be computed for ids whose enabledPlugins
  # this invocation can actually read: user scope (global) and the current
  # PROJECT_ROOT'"'"'s project/local scope. A project/local install belonging to a
  # DIFFERENT repo is excluded rather than asserted missing.
  | ([$installed[] | select(.scope == "user" or .currentProject == true) | .id] | unique) as $verifiable_ids
  # Ids the marketplace entry ships with defaultEnabled:false — a publisher'"'"'s
  # deliberate opt-in-required default. No enabledPlugins entry anywhere for
  # one of these is the INTENDED state, not a completeness gap.
  | ([$catalog[0].plugins[]? | select(.defaultEnabled == false) | .name + "@" + $name]) as $default_disabled
  | (reduce $known_at_mp[] as $id ({}; . + {($id): $ctx.effective[$id]})) as $enabled_at_mp
  # Delisted is proved from catalog NAMES, not catalog_versions keys. An
  # object-sourced entry never reaches catalog_versions and must not look
  # removed. A valid catalog whose plugins array is empty is not evidence that
  # every install was removed, so that shape yields no delisted set. Only an
  # install can take the uninstall remedy; a key with no install record is a
  # settings entry, and only a true one loads anything.
  | (if ($catalog[0].plugins | type) == "array" and ($catalog[0].plugins | length) > 0 then
       {installed: ($user_installed_ids - $catalog_ids),
        project: ([$installed[] | select(.currentProject == true)
                   | select(.id as $i | $catalog_ids | index($i) | not)
                   | {id, scope}] | unique),
        any_installed: ($installed_ids - $catalog_ids),
        settings_only: (([$enabled_at_mp | to_entries[] | select(.value == true) | .key]
                         - $installed_ids) - $catalog_ids)}
     else {installed: [], project: [], any_installed: [], settings_only: []} end) as $absent
  # A delisted install takes the uninstall remedy, so enabling it would contradict the report.
  | ((($verifiable_ids - $known_at_mp) - $default_disabled) - $absent.any_installed) as $missing_from_enabled
  # `versionsMatch` separates a benign multi-scope install (project and user
  # scope both pinned to the same version — normal, not actionable) from a
  # real version skew (some scope is behind another — the "run converge"
  # signal). A record count alone conflates the two.
  | ($installed | group_by(.id)
      | map(select(length > 1))
      | map({
          id: .[0].id,
          scopes: map({scope, version, projectPath, projectPathPresent, projectPathIsHome, linkedWorktree,
                       projectEnabledEntry, label}),
          versionsMatch: ((map(.version) | unique | length) == 1)
        })) as $divergences
  | {
      marketplace: {name: $name, autoUpdate: ($au == "true"), lastUpdated: $lastUpdated,
                    source: (if $src == "" then null else $src end)},
      project_root: (if ($cur | length) > 0 then $cur else null end),
      catalog: $catalog_names,
      catalog_versions: $cv,
      installed: $installed,
      enabled: $enabled_at_mp,
      missing_from_install: $missing_from_install,
      missing_from_user_install: $missing_from_user_install,
      missing_from_enabled: $missing_from_enabled,
      user_scope_orphans: $user_scope_orphans,
      delisted: $absent.installed,
      delisted_project: $absent.project,
      delisted_settings_only: $absent.settings_only,
      divergences: $divergences
    } as $block
  | '"$PROJECTION_PROGRAM"

emit_marketplace() {
  local name="$1"
  local i idx=-1 auto_update_json=false last_updated install_location source_text catalog_json

  for ((i = 0; i < ${#mp_keys[@]}; i++)); do
    if [[ "${mp_keys[i]}" == "$name" ]]; then
      idx=$i
      break
    fi
  done
  if ((idx < 0)); then
    error_block_to FS_BLOCK "$name" "not found in known_marketplaces.json"
    return 1
  fi
  [[ "${mp_au[idx]}" == "true" ]] && auto_update_json=true
  last_updated="${mp_lu[idx]}"
  install_location="${mp_loc[idx]}"
  source_text="${mp_src[idx]:-}"

  if [[ -n "${FLEET_STATE_CATALOG_DIR:-}" ]]; then
    local fixture="$FLEET_STATE_CATALOG_DIR/$name.json"
    read_set "$fixture"
    if [[ ! -f "$fixture" ]]; then
      error_block_to FS_BLOCK "$name" "no catalog fixture" "$auto_update_json" "$last_updated"
      return 1
    fi
    catalog_json="$fixture"
  else
    catalog_json="$install_location/.claude-plugin/marketplace.json"
    read_set "$catalog_json"
    if [[ ! -f "$catalog_json" ]]; then
      error_block_to FS_BLOCK "$name" "marketplace.json not found at installLocation" "$auto_update_json" "$last_updated"
      return 1
    fi
  fi

  local pass2=""
  jq_to pass2 -rn --rawfile c "$catalog_json" "$PASS2_PROGRAM" || pass2="INVALID"
  if [[ "$pass2" == "INVALID"* ]]; then
    error_block_to FS_BLOCK "$name" "marketplace.json is not valid JSON" "$auto_update_json" "$last_updated"
    return 1
  fi

  local manifest_base
  if [[ -n "${FLEET_STATE_CATALOG_DIR:-}" ]]; then
    manifest_base="$FLEET_STATE_CATALOG_DIR/$name"
  else
    manifest_base="${install_location//\\//}"
  fi

  local -a cv_names=() cv_manifests=() prime=("$manifest_base")
  local cv_tag cv_name cv_src cv_rel cv_manifest
  while IFS=$'\x1f' read -r cv_tag cv_name cv_src; do
    [[ "$cv_tag" == "E" ]] || continue
    cv_rel="${cv_src#./}"
    cv_rel="${cv_rel//\\//}"
    case "/$cv_rel/" in
    */../*)
      cv_rel=""
      ;;
    *) ;;
    esac
    cv_manifest=""
    [[ -z "$cv_rel" ]] || read_set "$manifest_base/$cv_rel/.claude-plugin/plugin.json"
    if [[ -n "$cv_rel" && -f "$manifest_base/$cv_rel/.claude-plugin/plugin.json" ]]; then
      cv_manifest="$manifest_base/$cv_rel/.claude-plugin/plugin.json"
      prime+=("$cv_manifest")
    fi
    cv_names+=("$cv_name")
    cv_manifests+=("$cv_manifest")
  done <<<"$pass2"
  hook::_physical_prime "${prime[@]}"

  local manifest_base_phys resolved contained bundle="" content
  hook::_physical_cached_to manifest_base_phys "$manifest_base" || true
  hook::normalize_path_to manifest_base_phys "$manifest_base_phys"
  manifest_base_phys="${manifest_base_phys%/}"

  for ((i = 0; i < ${#cv_names[@]}; i++)); do
    content=""
    cv_manifest="${cv_manifests[i]}"
    if [[ -n "$cv_manifest" && -n "$manifest_base_phys" ]]; then
      contained=0
      if hook::_physical_cached_to resolved "$cv_manifest"; then
        hook::normalize_path_to resolved "$resolved"
        [[ "$resolved" == "$manifest_base_phys"/* ]] && contained=1
      fi
      if ((contained)); then
        IFS= read -r -d '' content <"$cv_manifest" || true
      fi
    fi
    bundle+="${cv_names[i]}"$'\x1e'"$content"$'\x1f'
  done

  jq_to FS_BLOCK -Rsrc \
    --slurpfile inst "$INSTALLED_JSON" \
    --slurpfile catalog "$catalog_json" \
    --arg name "$name" \
    --arg au "$auto_update_json" \
    --arg lastUpdated "$last_updated" \
    --arg src "$source_text" \
    --arg cur "$current_project_norm" \
    --arg ci "$case_insensitive_os" \
    --arg home "${HOME:-}" \
    --arg selector "$IDS_SELECTOR" \
    "$PASS3_PROGRAM" <<<"$ctx_json"$'\x1d'"$presence_tsv"$'\x1d'"$bundle"$'\x1d'"$settings_bundle"
}

emit_one() {
  local rc=0
  emit_marketplace "$1" || rc=$?
  if [[ -n "$FS_BLOCK" ]]; then
    if [[ "$rc" -ne 0 && -n "$IDS_SELECTOR" ]]; then
      printf '%s\n' "$FS_BLOCK" >&2
    else
      printf '%s\n' "$FS_BLOCK"
    fi
  fi
  return "$rc"
}

if [[ "$MODE" == "default" && -z "$resolved_target" && -n "$phys_root" ]]; then
  mk_probe="$phys_root"
  for ((walk_level = 0; walk_level < 32; walk_level++)); do
    mk_manifest="$mk_probe/.claude-plugin/marketplace.json"
    read_set "$mk_manifest"
    if [[ -f "$mk_manifest" ]]; then
      mk_candidate=""
      jq_to mk_candidate -r '.name // "" | if type == "string" then . else "" end' \
        "$mk_manifest" 2>/dev/null || mk_candidate=""
      if [[ -n "$mk_candidate" ]]; then
        for mk_known in ${mp_names[@]+"${mp_names[@]}"}; do
          if [[ "$mk_known" == "$mk_candidate" ]]; then
            resolved_target="$mk_candidate"
            break
          fi
        done
      fi
      break
    fi
    mk_parent="${mk_probe%/*}"
    [[ -n "$mk_parent" && "$mk_parent" != "$mk_probe" ]] || break
    mk_probe="$mk_parent"
  done
fi

if [[ "$MODE" == "default" && -z "$resolved_target" ]]; then
  resolved_target="$location_target"
fi

case "$MODE" in
default)
  TARGET="$resolved_target"
  if [[ -z "$TARGET" ]]; then
    echo "ERROR: could not resolve the default marketplace. This plugin's install dir" >&2
    echo "  ${norm_root:-<unresolved>}" >&2
    echo "resolved through none of the three stages: exact installPath, version-agnostic" >&2
    echo ".../cache/<marketplace>/<plugin> prefix, and (for a root outside the cache) a" >&2
    echo ".claude-plugin/marketplace.json walk-up or a known marketplace installLocation." >&2
    echo "Either the session's loaded version differs from the installed one and the cache" >&2
    echo "layout is not the expected .../cache/<marketplace>/<plugin>/<version> shape, or" >&2
    echo "the root is not under the cache at all (a local dev checkout, --plugin-dir, or a" >&2
    echo "marketplace checkout) and carries no marketplace.json naming a marketplace that" >&2
    echo "known_marketplaces.json knows. Pass --marketplace <name> explicitly." >&2
    exit 1
  fi
  emit_one "$TARGET" || exit $?
  ;;
single)
  emit_one "$TARGET" || exit $?
  ;;
all)
  result='{"marketplaces":{'
  sep=""
  for n in ${mp_names[@]+"${mp_names[@]}"}; do
    [[ -n "$n" ]] || continue
    emit_marketplace "$n" || true
    json_string_to key_json "$n"
    result+="$sep$key_json:$FS_BLOCK"
    sep=","
  done
  result+='}}'
  printf '%s\n' "$result"
  ;;
*)
  echo "ERROR: unreachable mode: $MODE" >&2
  exit 2
  ;;
esac
