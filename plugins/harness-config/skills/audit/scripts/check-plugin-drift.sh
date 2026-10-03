#!/usr/bin/env bash
# Plugin drift audit for the audit skill (Category E).
#
# Compares a settings file's `enabledPlugins` against the catalog
# `marketplace.json` of each marketplace declared in that file's
# extraKnownMarketplaces. Reports drift modes that a state-vs-settings
# bootstrap check misses:
#
#   ORPHAN     plugin in enabledPlugins, NOT in upstream catalog, and not a null
#              entry in that catalog's renames map (deleted upstream, or a
#              renames chain that cycles)
#   NEW        plugin in upstream catalog with no enabledPlugins entry in this
#              file (added upstream). Report only: nothing proposes an entry.
#   RENAME     an orphan key the catalog renames map sends to a name, followed
#              to the end of the chain (source "renames"), or, when the map
#              does not mention the key, an ORPHAN + NEW pair with similar
#              names (source "heuristic")
#   REMOVED    an orphan key the catalog renames map sends to null. Not an
#              orphan row and not a rename.
#
# Coverage: only marketplaces this file declares are diffed. Every run prints
# the file's enabledPlugins keys whose marketplace it does not declare as "not
# diffed", with the count and the keys, including when it declares none.
#
# Catalog resolution per marketplace, by `extraKnownMarketplaces[key].source`:
#   directory  `source.source == "directory"` with a `path`. The catalog is
#              read from `<path>/.claude-plugin/marketplace.json` on disk. A
#              relative path (including `./`) resolves against the project
#              root, the directory that contains the settings file's
#              `.claude/`; an absolute path is used as is. Takes precedence
#              over `source.repo` when both are present, and never consults
#              SETTINGS_AUDIT_FIXTURE_DIR.
#   repo       `source.repo` (owner/name). When SETTINGS_AUDIT_FIXTURE_DIR is set,
#              the catalog is read from that directory and nowhere else. Otherwise
#              the local Claude Code clone is tried first. The config root is
#              CLAUDE_CONFIG_DIR when that is set, else ~/.claude. The catalog is
#              `<root>/plugins/marketplaces/<key>/.claude-plugin/marketplace.json`,
#              or, when that file is absent, `<installLocation>/.claude-plugin/marketplace.json`
#              for the installLocation `known_marketplaces.json` records for the
#              key. A readable valid catalog from either place is source
#              "local-clone" and the network is not contacted. Otherwise the
#              catalog is fetched from raw.githubusercontent.com. A repo that is
#              not owner/name in GitHub's name characters is reported SKIP. A
#              local-clone read only reads.
#   neither    reported SKIP.
#
# Keys are carried as JSON from the settings file and the catalog to the
# findings, so a key holding a carriage return or any other character reaches
# the JSON exactly. Displayed text prints control characters as `?`.
#
# Read-only. Network-tolerant: a marketplace whose upstream fetch fails, or
# whose directory catalog is missing or invalid, is reported SKIP and does not
# fail the run. Outputs a structured table to stdout and a machine-readable
# JSON to $SETTINGS_AUDIT_OUTPUT_JSON when set (consumed by fix-plugin-drift.sh).
# Each JSON block carries `source: "directory" | "repo" | "local-clone"` naming
# which resolution produced it. A rename row carries its own `source`:
# `"renames"` when the catalog map named the final plugin, `"heuristic"` when
# the similarity fallback did. A removed row carries
# `reason: "removed per catalog renames map"`. An orphan whose renames chain
# repeats a name carries `reason: "renames chain cycles"` and no rename row.
#
# Exit codes:
#   0  no orphan and no removed entry (NEW entries alone, which are report
#      only, exit 0)
#   1  an orphan or a removed entry was found (advisory, the invoker
#      decides whether to fix)
#   2  fatal (settings.json missing/invalid, jq missing). A missing curl is
#      not fatal: directory-sourced catalogs still audit, and each
#      repo-sourced one is recorded as a fetch failure.
#
# Env overrides (for testing):
#   CLAUDE_SETTINGS_FILE        path to project settings.json
#   SETTINGS_AUDIT_FIXTURE_DIR  directory of fixture marketplace.json files
#                               named <marketplace-key>.json. When set, the
#                               script reads repo-sourced catalogs from that
#                               directory and does not read a local clone or
#                               the network. Directory-sourced catalogs ignore it.
#   SETTINGS_AUDIT_OUTPUT_JSON  write structured findings to this path
#   NO_COLOR                    disable ANSI output

# The jq programs below are single-quoted on purpose: $name is a jq variable.
# shellcheck disable=SC2016
set -uo pipefail

# --- Config resolution -------------------------------------------------------

# The project-root ladder is shared vocabulary (lib/resolve-scopes.sh), not this
# script's to restate. Fail loudly rather than fall through: an unsourced library
# leaves the root empty and the settings path would name a file at the
# filesystem root.
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
  # Initialized here so ShellCheck SC2154 sees the assignment; the ladder fills it in.
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

# --- Output helpers ----------------------------------------------------------

if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
  RED="" YELLOW="" GREEN="" CYAN="" RESET=""
else
  RED=$'\033[31m' YELLOW=$'\033[33m' GREEN=$'\033[32m' CYAN=$'\033[36m' RESET=$'\033[0m'
fi

ORPHAN_TOTAL=0
NEW_TOTAL=0
REMOVED_TOTAL=0
SKIPPED_MARKETS=()

# One compact JSON block per marketplace, one per line, slurped into the array
# written at the end. Each block: { "key": "...", "status": "ok|skipped",
# "source": "directory|repo|local-clone", "skip_reason": "...", "orphans": [...],
# "new_upstream": [...], "renames": [...], "removed": [...] }. Held as JSON text, so a key's
# bytes never pass through a line-oriented tool. An orphan's `enabled` is the
# key's value exactly as the file holds it, which need not be a boolean; only
# an exact `false` is a removal candidate.
JSON_LINES=""

# Shared jq definitions. `san` is for display only: every control character,
# a carriage return included, prints as `?`, so no display line carries one and
# the carriage return a native-Windows jq appends to each line can be dropped
# wholesale. `mk($i)` is marketplace number $i in sorted key order. Every
# variable is a parameter, because jq 1.6 refuses to compile a def naming an
# unbound variable even when the program never calls it.
JQ_DEFS='def san: tostring | gsub("[[:cntrl:]]"; "?");
def mk($i): .extraKnownMarketplaces as $m | ($m | keys[$i]) as $k | {key: $k, value: $m[$k]};
def ep: .enabledPlugins | if type == "object" then . else {} end;'

# mk_raw <index> <jq expression over mk> - one field of marketplace <index>,
# printed with -j so no line terminator is appended. Used for paths, URLs and
# display, never for a key that is written back.
mk_raw() {
  jq -j --argjson i "$1" "$JQ_DEFS mk(\$i) | $2" "$SETTINGS"
}

# display_lines - the sanitized display lines a jq program prints, with the
# terminator carriage returns a native-Windows jq appends removed. Safe because
# `san` already replaced every carriage return that belonged to the data.
display_lines() {
  tr -d '\r'
}

# --- Rename heuristic ---------------------------------------------------------

# Similar names are likely renames: same prefix or suffix of >= 4 chars, OR one
# contained in the other with >= 5 chars. Cheap; false positives surface as
# RENAME warnings (human reviews) so over-matching is safer than under-matching.
# Computed in jq over the exact names, so the pairs it emits carry exact keys.
JQ_SIMILAR='def similar($a; $b):
  (($a | length) >= 4 and ($b | length) >= 4 and ($a[0:4] == $b[0:4] or $a[-4:] == $b[-4:]))
  or (($a | length) >= 5 and ($b | contains($a)))
  or (($b | length) >= 5 and ($a | contains($b)));'

# Follow one orphan through the catalog renames object. The walk is bounded by
# the number of keys, and a name already seen ends it, so a cycle cannot hang
# the check and is not given a final name. A start the map does not contain is
# "absent" (the similarity fallback applies). A value of null is "removed".
# A string value is the next name. Anything else is "bad" and is not a rename.
# `$state` is bound before any pipe, because a pipe makes `.` the value on its
# left and a later `.cur` would then index that value.
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

# --- Fetch upstream marketplace.json ----------------------------------------

# Stdout: the fixture catalog; nonzero when the fixture dir has no file for
# this key. The fixture dir, when set, is the only repo-source the check reads.
fetch_fixture() {
  local market_key="$1"
  local fixture="${SETTINGS_AUDIT_FIXTURE_DIR:-}/$market_key.json"
  if [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" && -f "$fixture" ]]; then
    cat "$fixture"
    return 0
  fi
  return 1
}

# Stdout: JSON content from raw.githubusercontent.com; nonzero on failure.
# curl is needed only here. A machine without it still audits every
# directory-sourced marketplace and every local clone; this marketplace is
# recorded as a fetch failure rather than aborting the run.
fetch_network() {
  local market_key="$1" repo="$2"
  if ! command -v curl >/dev/null 2>&1; then
    echo "WARN: curl not found; cannot fetch ${market_key//[[:cntrl:]]/?} from $repo" >&2
    return 1
  fi
  # --globoff: the URL is literal, never a curl range or set pattern.
  local url="https://raw.githubusercontent.com/$repo/HEAD/.claude-plugin/marketplace.json"
  curl -fsSL --globoff --max-time 15 "$url" 2>/dev/null
}

# claude_config_root - CLAUDE_CONFIG_DIR when set, else ~/.claude. Empty when
# neither is set. Printed with no trailing newline.
claude_config_root() {
  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    printf '%s' "${CLAUDE_CONFIG_DIR%/}"
  elif [[ -n "${HOME:-}" ]]; then
    printf '%s' "${HOME%/}/.claude"
  fi
}

# key_is_one_segment - a marketplace key that can be one directory name. A key
# containing a slash, a backslash, a newline, or the names `.` or `..` is not
# joined onto the clone path.
key_is_one_segment() {
  local k="$1"
  [[ -n "$k" && "$k" != "." && "$k" != ".." && "$k" != */* && "$k" != *\\* && "$k" != *$'\n'* ]]
}

# read_catalog_file <path> - stdout the file when it is a readable regular file
# of valid JSON. Reads only; a missing or invalid file returns 1 and prints
# nothing.
read_catalog_file() {
  local path="$1" json
  [[ -f "$path" && -r "$path" ]] || return 1
  json=$(cat "$path") || return 1
  jq empty <<<"$json" 2>/dev/null || return 1
  printf '%s' "$json"
}

# read_local_catalog <market_key> - stdout a valid catalog from the local
# Claude Code clone, or return 1. Tries the conventional clone path first, then
# the installLocation recorded for the key. Never writes.
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

# Remediation this check prints. A settings file can be edited here, or a
# Claude Code session in this checkout can rewrite it and the rewrite committed.
# A managed settings file is not rewritten that way: update managed enabledPlugins.
REMEDIATION_RENAME_FILE="replace the key in this file, or open a Claude Code session in this checkout and commit the rewrite it makes"
REMEDIATION_REMOVED_FILE="remove the key from this file, or open a Claude Code session in this checkout and commit the rewrite it makes"
REMEDIATION_MANAGED="update managed enabledPlugins"

# settings_file_is_managed - the audited path is managed settings: the file is
# named managed-settings.json or remote-settings.json, or it sits in
# managed-settings.d.
settings_file_is_managed() {
  local base parent
  base=$(basename -- "$SETTINGS")
  parent=$(basename -- "$(dirname -- "$SETTINGS")")
  [[ "$base" == "managed-settings.json" || "$base" == "remote-settings.json" || "$parent" == "managed-settings.d" ]]
}

# --- Resolve a directory-source path ----------------------------------------

# Stdout: the directory a `source.path` names. A relative path (including
# `./`) resolves against the project root, the directory that contains the
# settings file's `.claude/`; an absolute path (POSIX or drive-lettered) is
# used as is. Backslashes become forward slashes and a trailing slash is
# stripped so Git Bash on Windows joins the same way as Linux.
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

# --- Per-marketplace audit --------------------------------------------------

# Record a skipped marketplace: print the SKIP line, append to SKIPPED_MARKETS,
# and add a skipped block whose key jq reads from the settings file. Args:
# index, display key, suffix, message, json_reason, source ("repo" when
# omitted). The reason and source are literals from this file.
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

  # A directory source wins over source.repo when both are present: the
  # catalog is already on disk, so no fetch and no fixture lookup happens.
  local catalog_source="repo" catalog_dir=""
  if [[ "$source_type" == "directory" && -n "$source_path" ]]; then
    catalog_source="directory"
    catalog_dir=$(resolve_directory_path "$source_path")
  fi

  # print_market_header <label> - the marketplace line above its rows.
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

    # The repo becomes part of a URL, so only an owner/name pair of GitHub's
    # name characters is fetched; `.` and `..` would walk the URL path.
    local repo_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
    if [[ ! "$repo" =~ $repo_re || "/$repo/" == *"/./"* || "/$repo/" == *"/../"* ]]; then
      print_market_header "$repo"
      record_skip "$index" "$display_key" "invalid-repo" \
        "source.repo is not owner/name: $repo" "invalid source.repo"
      return 0
    fi

    # The fixture directory wins over a local clone and over the network, so a
    # test names the catalog it means. With no fixture directory, a readable
    # local clone wins over the network and is labeled local-clone.
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

  # The whole comparison happens in jq: the catalog on stdin, the settings
  # file slurped, the marketplace key read from it by index. Names are
  # compared as JSON strings, so nothing is trimmed from a key. The renames
  # map is read from the catalog already in hand. An orphan the map does not
  # mention keeps the similarity fallback.
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
       orphans: [$class[] | select(.follow.kind != "removed")
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

  # --- Render -----------------------------------------------------------------

  local orphan_count new_count removed_count local_count upstream_count
  orphan_count=$(jq -j '.orphans | length' <<<"$block")
  new_count=$(jq -j '.new_upstream | length' <<<"$block")
  removed_count=$(jq -j '.removed | length' <<<"$block")
  local_count=$(jq -j --argjson i "$index" "$JQ_DEFS"'mk($i).key as $k | [ep | keys[] | select(endswith("@" + $k))] | length' "$SETTINGS")
  upstream_count=$(jq -j '[.plugins[]? | objects | .name | strings] | unique | length' <<<"$upstream_json")
  ORPHAN_TOTAL=$((ORPHAN_TOTAL + orphan_count))
  NEW_TOTAL=$((NEW_TOTAL + new_count))
  REMOVED_TOTAL=$((REMOVED_TOTAL + removed_count))

  if [[ "$orphan_count" -eq 0 && "$new_count" -eq 0 && "$removed_count" -eq 0 ]]; then
    printf '  %sOK%s    no drift (%d local, %d upstream)\n' \
      "$GREEN" "$RESET" "$local_count" "$upstream_count"
  fi

  local line enabled entry rest reason marker
  if [[ "$orphan_count" -gt 0 ]]; then
    printf '  %sORPHAN%s  %d entries in the settings file no longer in upstream:\n' \
      "$RED" "$RESET" "$orphan_count"
    # Tabs separate the value, the entry and an optional reason; `san` turned
    # any tab in the data into `?`, so the split is unambiguous. Only an exact
    # false is a removal candidate; true and every other value are left to a person.
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
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '    - %s\n' "$line"
    done < <(jq -r "$JQ_DEFS"'.removed[] | .name + "@" + .marketplace | san' <<<"$block" | display_lines)
  fi

  if [[ "$new_count" -gt 0 ]]; then
    printf '  %sNEW%s     %d upstream plugins with no entry in the settings file (report only):\n' \
      "$CYAN" "$RESET" "$new_count"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '    - %s\n' "$line"
    done < <(jq -r "$JQ_DEFS"'.new_upstream[] | .name + "@" + .marketplace | san' <<<"$block" | display_lines)
  fi

  local catalog_renames heuristic_renames rename_fix
  catalog_renames=$(jq -j '[.renames[] | select(.source == "renames")] | length' <<<"$block")
  heuristic_renames=$(jq -j '[.renames[] | select(.source != "renames")] | length' <<<"$block")
  if [[ "$catalog_renames" -gt 0 ]]; then
    rename_fix="$REMEDIATION_RENAME_FILE"
    settings_file_is_managed && rename_fix="$REMEDIATION_MANAGED"
    printf '  %sRENAME%s   %d catalog renames (%s):\n' \
      "$YELLOW" "$RESET" "$catalog_renames" "$rename_fix"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '    - %s\n' "$line"
    done < <(jq -r "$JQ_DEFS"'.renames[] | select(.source == "renames") | "\(.from | san) -> \(.to | san)"' <<<"$block" | display_lines)
  fi
  if [[ "$heuristic_renames" -gt 0 ]]; then
    printf '  %sRENAME?%s possible rename pairs (heuristic, review manually):\n' \
      "$YELLOW" "$RESET"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '    - %s\n' "$line"
    done < <(jq -r "$JQ_DEFS"'.renames[] | select(.source != "renames") | "\(.from | san) -> \(.to | san)"' <<<"$block" | display_lines)
  fi
}

# --- Coverage ----------------------------------------------------------------

# print_coverage - the audited file's enabledPlugins keys whose marketplace it
# does not declare. They are never compared against any catalog, so the run
# names them rather than letting silence read as "no drift". Printed on every
# path, including when no marketplace is declared.
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

# write_findings - the blocks as one JSON array to $SETTINGS_AUDIT_OUTPUT_JSON
# when it is set; with no block that is `[]`, never a missing document.
write_findings() {
  [[ -n "${SETTINGS_AUDIT_OUTPUT_JSON:-}" ]] || return 0
  if ! jq -s '.' <<<"$JSON_LINES" >"$SETTINGS_AUDIT_OUTPUT_JSON"; then
    echo "ERROR: cannot write findings JSON to ${SETTINGS_AUDIT_OUTPUT_JSON//[[:cntrl:]]/?}" >&2
    exit 2
  fi
  printf '  JSON written to: %s\n' "${SETTINGS_AUDIT_OUTPUT_JSON//[[:cntrl:]]/?}"
}

# --- Main --------------------------------------------------------------------

main() {
  printf '%sPlugin drift audit%s\n' "$CYAN" "$RESET"
  printf 'Settings file: %s\n' "${SETTINGS//[[:cntrl:]]/?}"
  if [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" ]]; then
    printf 'Source: %sfixtures%s (%s)\n' "$YELLOW" "$RESET" "$SETTINGS_AUDIT_FIXTURE_DIR"
  else
    printf 'Source: local clone when present, else live upstream (raw.githubusercontent.com)\n'
  fi

  local market_count
  # An array would yield its indices as marketplace names, so only an object is read.
  if ! market_count=$(jq -j '.extraKnownMarketplaces // {}
    | if type != "object" then error("not an object") else keys | length end' "$SETTINGS"); then
    echo "ERROR: cannot read extraKnownMarketplaces from $SETTINGS" >&2
    exit 2
  fi

  # The basis of the audit: only these marketplaces are compared, so a plugin
  # from any other marketplace is outside what this run can report on.
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
  if [[ "$ORPHAN_TOTAL" -eq 0 && "$NEW_TOTAL" -eq 0 && "$REMOVED_TOTAL" -eq 0 && "${#SKIPPED_MARKETS[@]}" -eq 0 ]]; then
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

  [[ "$ORPHAN_TOTAL" -eq 0 && "$REMOVED_TOTAL" -eq 0 ]] && exit 0
  exit 1
}

main "$@"
