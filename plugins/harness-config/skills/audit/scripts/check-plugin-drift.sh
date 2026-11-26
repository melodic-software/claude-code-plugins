#!/usr/bin/env bash
# Exit codes:
#   0  no orphan and no removed entry (NEW entries alone, which are report
#      only, exit 0)
#   1  an orphan or a removed entry was found (advisory, the invoker
#      decides whether to fix)
#   2  fatal (settings.json missing/invalid, jq missing). A missing curl is
#      not fatal: directory-sourced catalogs still audit, and each
#      repo-sourced one is recorded as a fetch failure.

# The jq programs below are single-quoted on purpose: $name is a jq variable.
# shellcheck disable=SC2016
set -uo pipefail


PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RESOLVE_SCOPES_LIB="$PLUGIN_ROOT/lib/resolve-scopes.sh"
if [[ ! -r "$RESOLVE_SCOPES_LIB" ]]; then
  echo "ERROR: cannot read $RESOLVE_SCOPES_LIB; the plugin's shared scope-resolution library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/resolve-scopes.sh
source "$RESOLVE_SCOPES_LIB"

if [[ -n "${CLAUDE_SETTINGS_FILE:-}" ]]; then
  SETTINGS="$CLAUDE_SETTINGS_FILE"
else
  PROJECT_ROOT=""
  scopes::project_root_to PROJECT_ROOT
  SETTINGS="$PROJECT_ROOT/.claude/settings.json"
fi

if [[ ! -f "$SETTINGS" ]]; then
  echo "ERROR: settings file not found: $SETTINGS" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi

if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "ERROR: settings file is not valid JSON: $SETTINGS" >&2
  exit 2
fi


if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
  RED="" YELLOW="" GREEN="" CYAN="" RESET=""
else
  RED=$'\033[31m' YELLOW=$'\033[33m' GREEN=$'\033[32m' CYAN=$'\033[36m' RESET=$'\033[0m'
fi

ORPHAN_TOTAL=0
NEW_TOTAL=0
REMOVED_TOTAL=0
RENAME_TOTAL=0
SKIPPED_MARKETS=()

JSON_LINES=""

JQ_DEFS='def san: tostring | gsub("[[:cntrl:]]"; "?");
def mk($i): .extraKnownMarketplaces as $m | ($m | keys[$i]) as $k | {key: $k, value: $m[$k]};
def ep: .enabledPlugins | if type == "object" then . else {} end;'

mk_raw() {
  jq -j --argjson i "$1" "$JQ_DEFS mk(\$i) | $2" "$SETTINGS"
}

display_lines() {
  tr -d '\r'
}

print_items() {
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] || printf '    - %s\n' "$line"
  done < <(jq -r "$JQ_DEFS $2" <<<"$1" | display_lines)
}


JQ_SIMILAR='def similar($a; $b):
  (($a | length) >= 4 and ($b | length) >= 4 and ($a[0:4] == $b[0:4] or $a[-4:] == $b[-4:]))
  or (($a | length) >= 5 and ($b | contains($a)))
  or (($b | length) >= 5 and ($a | contains($b)));'

JQ_FOLLOW='def follow($map; $start):
  (($map | keys) | length) as $limit
  | reduce range(0; $limit + 1) as $step (
      {cur: $start, seen: [], kind: "walk"};
      . as $state
      | if $state.kind != "walk" then $state
        elif ($state.seen | index($state.cur)) != null then $state | .kind = "cycle"
        elif ($map | has($state.cur) | not) then
          if ($state.seen | length) == 0 then $state | .kind = "absent"
          else $state | .kind = "rename" | .to = $state.cur
          end
        else
          ($map[$state.cur]) as $v
          | $state
          | .seen += [$state.cur]
          | if $v == null then .kind = "removed"
            elif ($v | type) == "string" then .cur = $v
            else .kind = "bad"
            end
        end)
  | if .kind == "walk" then .kind = "cycle" else . end;'


fetch_fixture() {
  local market_key="$1"
  local fixture="${SETTINGS_AUDIT_FIXTURE_DIR:-}/$market_key.json"
  if [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" && -f "$fixture" ]]; then
    cat "$fixture"
    return 0
  fi
  return 1
}

fetch_network() {
  local market_key="$1" repo="$2"
  if ! command -v curl >/dev/null 2>&1; then
    echo "WARN: curl not found; cannot fetch ${market_key//[[:cntrl:]]/?} from $repo" >&2
    return 1
  fi
  local url="https://raw.githubusercontent.com/$repo/HEAD/.claude-plugin/marketplace.json"
  curl -fsSL --globoff --max-time 15 "$url" 2>/dev/null
}

claude_config_root() {
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    printf '%s' "${CLAUDE_CONFIG_DIR%/}"
  elif [[ -n "${HOME:-}" ]]; then
    printf '%s' "${HOME%/}/.claude"
  fi
}

key_is_one_segment() {
  local k="$1"
  [[ -n "$k" && "$k" != "." && "$k" != ".." && "$k" != */* && "$k" != *\\* && "$k" != *$'\n'* ]]
}

read_catalog_file() {
  local path="$1" json
  [[ -f "$path" && -r "$path" ]] || return 1
  json=$(cat "$path") || return 1
  jq empty <<<"$json" 2>/dev/null || return 1
  printf '%s' "$json"
}

read_local_catalog() {
  local market_key="$1" root known loc
  root=$(claude_config_root)
  [[ -n "$root" ]] || return 1

  if key_is_one_segment "$market_key"; then
    if read_catalog_file "$root/plugins/marketplaces/$market_key/.claude-plugin/marketplace.json"; then
      return 0
    fi
  fi

  known="$root/plugins/known_marketplaces.json"
  [[ -f "$known" && -r "$known" ]] || return 1
  loc=$(jq -j --arg k "$market_key" '
    if type == "object" and (.[$k].installLocation | type) == "string"
    then .[$k].installLocation else empty end' "$known") || return 1
  loc="${loc%$'\r'}"
  loc="${loc%/}"
  [[ -n "$loc" ]] || return 1
  read_catalog_file "$loc/.claude-plugin/marketplace.json"
}

REMEDIATION_RENAME_FILE="replace the key in this file, or open a Claude Code session in this checkout and commit the rewrite it makes"
REMEDIATION_REMOVED_FILE="remove the key from this file, or open a Claude Code session in this checkout and commit the rewrite it makes"
REMEDIATION_MANAGED="update managed enabledPlugins"

settings_file_is_managed() {
  local base parent
  base=$(basename -- "$SETTINGS")
  parent=$(basename -- "$(dirname -- "$SETTINGS")")
  [[ "$base" == "managed-settings.json" || "$base" == "remote-settings.json" || "$parent" == "managed-settings.d" ]]
}


resolve_directory_path() {
  local raw="$1"
  raw="${raw//\\//}"
  raw="${raw#./}"
  raw="${raw%/}"

  if [[ "$raw" == /* || "$raw" == [A-Za-z]:/* ]]; then
    printf '%s\n' "$raw"
    return 0
  fi

  local project_root
  project_root=$(dirname "$(dirname "$SETTINGS")")
  if [[ -z "$raw" || "$raw" == "." ]]; then
    printf '%s\n' "$project_root"
  else
    printf '%s/%s\n' "$project_root" "$raw"
  fi
}


record_skip() {
  local index="$1" display_key="$2" suffix="$3" message="$4" json_reason="$5" source="${6:-repo}"
  local block
  printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$message"
  SKIPPED_MARKETS+=("$display_key:$suffix")
  if ! block=$(jq -c --argjson i "$index" --arg r "$json_reason" --arg s "$source" \
    "$JQ_DEFS"'{key: mk($i).key, status: "skipped", source: $s, skip_reason: $r, orphans: [], new_upstream: [], renames: [], removed: []}' \
    "$SETTINGS"); then
    echo "ERROR: cannot record the skipped marketplace $display_key" >&2
    exit 2
  fi
  JSON_LINES+="$block"$'\n'
}

audit_marketplace() {
  local index="$1"
  local market_key display_key repo source_type source_path
  market_key=$(mk_raw "$index" '.key')
  display_key=$(mk_raw "$index" '.key | san')
  repo=$(mk_raw "$index" '(.value.source.repo? | strings) // empty | san')
  source_type=$(mk_raw "$index" '(.value.source.source? | strings) // empty')
  source_path=$(mk_raw "$index" '(.value.source.path? | strings) // empty')

  local catalog_source="repo" catalog_dir=""
  if [[ "$source_type" == "directory" && -n "$source_path" ]]; then
    catalog_source="directory"
    catalog_dir=$(resolve_directory_path "$source_path")
  fi

  print_market_header() {
    printf '\n%s%s%s (%s)\n' "$CYAN" "$display_key" "$RESET" "$1"
  }

  local upstream_json
  if [[ "$catalog_source" == "directory" ]]; then
    print_market_header "directory:${catalog_dir//[[:cntrl:]]/?}"
    local catalog_file="$catalog_dir/.claude-plugin/marketplace.json"
    if [[ ! -f "$catalog_file" ]]; then
      record_skip "$index" "$display_key" "catalog-missing" \
        "directory catalog not found at ${catalog_file//[[:cntrl:]]/?}" "directory catalog missing" "directory"
      return 0
    fi
    upstream_json=$(cat "$catalog_file")
    if ! jq empty <<<"$upstream_json" 2>/dev/null; then
      record_skip "$index" "$display_key" "invalid-catalog" \
        "directory catalog is not valid JSON: ${catalog_file//[[:cntrl:]]/?}" "invalid directory catalog" "directory"
      return 0
    fi
  else
    if [[ -z "$repo" ]]; then
      print_market_header "${repo:-no-repo}"
      record_skip "$index" "$display_key" "no-repo" "no source.repo declared" "no source.repo"
      return 0
    fi

    local repo_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
    if [[ ! "$repo" =~ $repo_re || "/$repo/" == *"/./"* || "/$repo/" == *"/../"* ]]; then
      print_market_header "$repo"
      record_skip "$index" "$display_key" "invalid-repo" \
        "source.repo is not owner/name: $repo" "invalid source.repo"
      return 0
    fi

    if [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" ]]; then
      print_market_header "$repo"
      if ! upstream_json=$(fetch_fixture "$market_key"); then
        record_skip "$index" "$display_key" "fetch-failed" \
          "upstream fetch failed (network/404/missing fixture)" "fetch failed"
        return 0
      fi
    elif upstream_json=$(read_local_catalog "$market_key"); then
      catalog_source="local-clone"
      print_market_header "local-clone"
    else
      print_market_header "$repo"
      if ! upstream_json=$(fetch_network "$market_key" "$repo"); then
        record_skip "$index" "$display_key" "fetch-failed" \
          "upstream fetch failed (network/404/missing fixture)" "fetch failed"
        return 0
      fi
    fi

    if ! jq empty <<<"$upstream_json" 2>/dev/null; then
      record_skip "$index" "$display_key" "invalid-json" "upstream returned invalid JSON" "invalid upstream JSON"
      return 0
    fi
  fi

  local block
  if ! block=$(jq -c --argjson i "$index" --arg src "$catalog_source" --slurpfile s "$SETTINGS" \
    "$JQ_DEFS $JQ_SIMILAR $JQ_FOLLOW"'
    ($s[0] | mk($i).key) as $k
    | ("@" + $k) as $suf
    | ([.plugins[]? | objects | .name | strings] | unique) as $up
    | [$s[0] | ep | to_entries[] | select(.key | endswith($suf))
        | {name: (.key | .[0:(length - ($suf | length))]), value}] as $pairs
    | ($pairs | map(.name) | unique) as $local
    | ($local - $up) as $orphans
    | ($up - $local) as $new
    | (.renames | if type == "object" then . else {} end) as $map
    | [$orphans[] as $o | follow($map; $o) as $f
        | {name: $o, follow: $f,
           enabled: ([$pairs[] | select(.name == $o)] | first | .value)}] as $class
    | {key: $k, status: "ok", source: $src, skip_reason: "",
       orphans: [$class[] | select(.follow.kind != "removed" and .follow.kind != "rename")
         | {name, marketplace: $k, enabled}
           + (if .follow.kind == "cycle" then {reason: "renames chain cycles"}
              elif .follow.kind == "bad" then {reason: "renames map value is not a name or null"}
              else {} end)],
       new_upstream: [$new[] | {name: ., marketplace: $k}],
       renames: (
         [$class[] | select(.follow.kind == "rename" and (.follow.to | type) == "string")
           | {from: .name, to: .follow.to, marketplace: $k, source: "renames"}]
         + [$class[] | select(.follow.kind == "absent") | .name as $o
           | $new[] as $n | select(similar($o; $n))
           | {from: $o, to: $n, marketplace: $k, source: "heuristic"}]),
       removed: [$class[] | select(.follow.kind == "removed")
         | {name, marketplace: $k, enabled, reason: "removed per catalog renames map"}]}
  ' <<<"$upstream_json"); then
    echo "ERROR: cannot compare marketplace $display_key against its catalog" >&2
    exit 2
  fi
  block="${block%$'\r'}"
  JSON_LINES+="$block"$'\n'


  local orphan_count new_count removed_count rename_count heuristic_count
  orphan_count=$(jq -j '.orphans | length' <<<"$block")
  new_count=$(jq -j '.new_upstream | length' <<<"$block")
  removed_count=$(jq -j '.removed | length' <<<"$block")
  rename_count=$(jq -j '[.renames[] | select(.source == "renames")] | length' <<<"$block")
  heuristic_count=$(jq -j '[.renames[] | select(.source != "renames")] | length' <<<"$block")
  ORPHAN_TOTAL=$((ORPHAN_TOTAL + orphan_count))
  NEW_TOTAL=$((NEW_TOTAL + new_count))
  REMOVED_TOTAL=$((REMOVED_TOTAL + removed_count))
  RENAME_TOTAL=$((RENAME_TOTAL + rename_count))

  if [[ "$orphan_count" -eq 0 && "$new_count" -eq 0 && "$removed_count" -eq 0 && "$rename_count" -eq 0 ]]; then
    local local_count upstream_count
    local_count=$(jq -j --argjson i "$index" "$JQ_DEFS"'mk($i).key as $k | [ep | keys[] | select(endswith("@" + $k))] | length' "$SETTINGS")
    upstream_count=$(jq -j '[.plugins[]? | objects | .name | strings] | unique | length' <<<"$upstream_json")
    printf '  %sOK%s    no drift (%d local, %d upstream)\n' \
      "$GREEN" "$RESET" "$local_count" "$upstream_count"
  fi

  local line enabled entry rest reason marker
  if [[ "$orphan_count" -gt 0 ]]; then
    printf '  %sORPHAN%s  %d entries in the settings file no longer in upstream:\n' \
      "$RED" "$RESET" "$orphan_count"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      enabled="${line%%$'\t'*}"
      rest="${line#*$'\t'}"
      entry="${rest%%$'\t'*}"
      reason="${rest#*$'\t'}"
      [[ "$reason" == "$entry" ]] && reason=""
      marker="$RED($enabled, manual review required)$RESET"
      [[ "$enabled" == "false" ]] && marker="$YELLOW(false, removal candidate)$RESET"
      if [[ -n "$reason" ]]; then
        printf '    - %-40s %s %s\n' "$entry" "$marker" "$reason"
      else
        printf '    - %-40s %s\n' "$entry" "$marker"
      fi
    done < <(jq -r "$JQ_DEFS"'.orphans[] | "\(.enabled | tojson | san)\t\(.name + "@" + .marketplace | san)\t\(.reason // "" | san)"' <<<"$block" | display_lines)
  fi

  if [[ "$removed_count" -gt 0 ]]; then
    local removed_fix="$REMEDIATION_REMOVED_FILE"
    settings_file_is_managed && removed_fix="$REMEDIATION_MANAGED"
    printf '  %sREMOVED%s %d entries the catalog renames map marks removed (%s):\n' \
      "$YELLOW" "$RESET" "$removed_count" "$removed_fix"
    print_items "$block" '.removed[] | .name + "@" + .marketplace | san'
  fi

  if [[ "$new_count" -gt 0 ]]; then
    printf '  %sNEW%s     %d upstream plugins with no entry in the settings file (report only):\n' \
      "$CYAN" "$RESET" "$new_count"
    print_items "$block" '.new_upstream[] | .name + "@" + .marketplace | san'
  fi

  if [[ "$rename_count" -gt 0 ]]; then
    local rename_fix="$REMEDIATION_RENAME_FILE"
    settings_file_is_managed && rename_fix="$REMEDIATION_MANAGED"
    printf '  %sRENAME%s   %d catalog renames (%s):\n' \
      "$YELLOW" "$RESET" "$rename_count" "$rename_fix"
    print_items "$block" '.renames[] | select(.source == "renames") | "\(.from | san) -> \(.to | san)"'
  fi
  if [[ "$heuristic_count" -gt 0 ]]; then
    printf '  %sRENAME?%s possible rename pairs (heuristic, review manually):\n' \
      "$YELLOW" "$RESET"
    print_items "$block" '.renames[] | select(.source != "renames") | "\(.from | san) -> \(.to | san)"'
  fi
}


print_coverage() {
  local line
  if ! line=$(jq -j "$JQ_DEFS"'
    (.extraKnownMarketplaces // {} | if type == "object" then keys else [] end) as $mks
    | [ep | keys[] | . as $key | select(any($mks[]; . as $m | $key | endswith("@" + $m)) | not)]
    | "\(length) enabledPlugins keys name a marketplace this file does not declare"
      + (if length > 0 then ": " + (map(san) | join(", ")) else "" end)
  ' "$SETTINGS"); then
    echo "ERROR: cannot read enabledPlugins from $SETTINGS" >&2
    exit 2
  fi
  printf 'Not diffed: %s\n' "$line"
}

write_findings() {
  [[ -n "${SETTINGS_AUDIT_OUTPUT_JSON:-}" ]] || return 0
  if ! jq -s '.' <<<"$JSON_LINES" >"$SETTINGS_AUDIT_OUTPUT_JSON"; then
    echo "ERROR: cannot write findings JSON to ${SETTINGS_AUDIT_OUTPUT_JSON//[[:cntrl:]]/?}" >&2
    exit 2
  fi
  printf '  JSON written to: %s\n' "${SETTINGS_AUDIT_OUTPUT_JSON//[[:cntrl:]]/?}"
}


main() {
  printf '%sPlugin drift audit%s\n' "$CYAN" "$RESET"
  printf 'Settings file: %s\n' "${SETTINGS//[[:cntrl:]]/?}"
  if [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" ]]; then
    printf 'Source: %sfixtures%s (%s)\n' "$YELLOW" "$RESET" "$SETTINGS_AUDIT_FIXTURE_DIR"
  else
    printf 'Source: local clone when present, else live upstream (raw.githubusercontent.com)\n'
  fi

  local market_count
  if ! market_count=$(jq -j '.extraKnownMarketplaces // {}
    | if type != "object" then error("not an object") else keys | length end' "$SETTINGS"); then
    echo "ERROR: cannot read extraKnownMarketplaces from $SETTINGS" >&2
    exit 2
  fi

  printf 'Marketplaces declared in the audited file: %d\n' "$market_count"
  print_coverage

  if [[ "$market_count" -eq 0 ]]; then
    printf '\n%sno marketplaces declared in extraKnownMarketplaces%s\n' "$YELLOW" "$RESET"
    write_findings
    exit 0
  fi

  local i
  for ((i = 0; i < market_count; i++)); do
    audit_marketplace "$i"
  done

  printf '\n%sSummary%s\n' "$CYAN" "$RESET"
  if [[ "$ORPHAN_TOTAL" -eq 0 && "$NEW_TOTAL" -eq 0 && "$REMOVED_TOTAL" -eq 0 && "$RENAME_TOTAL" -eq 0 && "${#SKIPPED_MARKETS[@]}" -eq 0 ]]; then
    printf '  %sOK%s    no drift detected\n' "$GREEN" "$RESET"
  fi
  [[ "$ORPHAN_TOTAL" -gt 0 ]] && printf '  %sDRIFT%s %d orphan entries, run fix-plugin-drift.sh to plan their removal\n' \
    "$RED" "$RESET" "$ORPHAN_TOTAL"
  [[ "$REMOVED_TOTAL" -gt 0 ]] && printf '  %sREMOVED%s %d entries the catalog renames map marks removed (report only)\n' \
    "$YELLOW" "$RESET" "$REMOVED_TOTAL"
  [[ "$NEW_TOTAL" -gt 0 ]] && printf '  %sNEW%s   %d upstream plugins with no entry in the settings file (report only)\n' \
    "$CYAN" "$RESET" "$NEW_TOTAL"
  [[ "${#SKIPPED_MARKETS[@]}" -gt 0 ]] && printf '  %sSKIP%s  %d marketplaces unreachable: %s\n' \
    "$YELLOW" "$RESET" "${#SKIPPED_MARKETS[@]}" "${SKIPPED_MARKETS[*]}"

  write_findings

  [[ "$ORPHAN_TOTAL" -eq 0 && "$REMOVED_TOTAL" -eq 0 && "$RENAME_TOTAL" -eq 0 ]] && exit 0
  exit 1
}

main "$@"
