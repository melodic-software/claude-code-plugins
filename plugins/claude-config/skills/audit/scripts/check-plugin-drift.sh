#!/usr/bin/env bash
# Plugin drift audit for the audit skill (Category E).
#
# Compares a settings file's `enabledPlugins` against the catalog
# `marketplace.json` of each marketplace declared in that file's
# extraKnownMarketplaces. Reports three drift modes that a state-vs-settings
# bootstrap check misses:
#
#   ORPHAN     plugin in enabledPlugins, NOT in upstream catalog (deleted upstream)
#   NEW        plugin in upstream catalog with no enabledPlugins entry in this
#              file (added upstream). Report only: nothing proposes an entry.
#   RENAME     heuristic: ORPHAN + NEW with similar names within one marketplace
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
#   repo       `source.repo` (owner/name). The catalog is fetched from
#              raw.githubusercontent.com, or read from the fixture directory
#              when SETTINGS_AUDIT_FIXTURE_DIR is set. A repo that is not
#              owner/name in GitHub's name characters is reported SKIP.
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
# Each JSON block carries `source: "directory" | "repo"` naming which
# resolution produced it.
#
# Exit codes:
#   0  no orphan (NEW entries alone, which are report only, exit 0)
#   1  an orphan was found (advisory, the invoker
#      decides whether to fix)
#   2  fatal (settings.json missing/invalid, jq missing). A missing curl is
#      not fatal: directory-sourced catalogs still audit, and each
#      repo-sourced one is recorded as a fetch failure.
#
# Env overrides (for testing):
#   CLAUDE_SETTINGS_FILE        path to project settings.json
#   SETTINGS_AUDIT_FIXTURE_DIR  directory of fixture marketplace.json files
#                               named <marketplace-key>.json. When set, the
#                               script reads repo-sourced catalogs from disk
#                               instead of curl. Directory-sourced catalogs
#                               ignore it.
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
SKIPPED_MARKETS=()

# One compact JSON block per marketplace, one per line, slurped into the array
# written at the end. Each block: { "key": "...", "status": "ok|skipped",
# "source": "directory|repo", "skip_reason": "...", "orphans": [...],
# "new_upstream": [...], "renames": [...] }. Held as JSON text, so a key's
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

# --- Fetch upstream marketplace.json ----------------------------------------

# Stdout: JSON content; nonzero exit on failure.
fetch_upstream() {
  local market_key="$1" repo="$2"

  if [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" ]]; then
    local fixture="$SETTINGS_AUDIT_FIXTURE_DIR/$market_key.json"
    if [[ -f "$fixture" ]]; then
      cat "$fixture"
      return 0
    fi
    return 1
  fi

  # curl is needed only here, for a repo-sourced catalog. A machine without
  # it still audits every directory-sourced marketplace; this one is
  # recorded as a fetch failure rather than aborting the run.
  if ! command -v curl >/dev/null 2>&1; then
    echo "WARN: curl not found; cannot fetch ${market_key//[[:cntrl:]]/?} from $repo" >&2
    return 1
  fi
  # --globoff: the URL is literal, never a curl range or set pattern.
  local url="https://raw.githubusercontent.com/$repo/HEAD/.claude-plugin/marketplace.json"
  curl -fsSL --globoff --max-time 15 "$url" 2>/dev/null
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
    "$JQ_DEFS"'{key: mk($i).key, status: "skipped", source: $s, skip_reason: $r, orphans: [], new_upstream: [], renames: []}' \
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

  if [[ "$catalog_source" == "directory" ]]; then
    printf '\n%s%s%s (directory:%s)\n' "$CYAN" "$display_key" "$RESET" "${catalog_dir//[[:cntrl:]]/?}"
  else
    printf '\n%s%s%s (%s)\n' "$CYAN" "$display_key" "$RESET" "${repo:-no-repo}"
  fi

  local upstream_json
  if [[ "$catalog_source" == "directory" ]]; then
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
      record_skip "$index" "$display_key" "no-repo" "no source.repo declared" "no source.repo"
      return 0
    fi

    # The repo becomes part of a URL, so only an owner/name pair of GitHub's
    # name characters is fetched; `.` and `..` would walk the URL path.
    local repo_re='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
    if [[ ! "$repo" =~ $repo_re || "/$repo/" == *"/./"* || "/$repo/" == *"/../"* ]]; then
      record_skip "$index" "$display_key" "invalid-repo" \
        "source.repo is not owner/name: $repo" "invalid source.repo"
      return 0
    fi

    if ! upstream_json=$(fetch_upstream "$market_key" "$repo"); then
      record_skip "$index" "$display_key" "fetch-failed" \
        "upstream fetch failed (network/404/missing fixture)" "fetch failed"
      return 0
    fi

    if ! jq empty <<<"$upstream_json" 2>/dev/null; then
      record_skip "$index" "$display_key" "invalid-json" "upstream returned invalid JSON" "invalid upstream JSON"
      return 0
    fi
  fi

  # The whole comparison happens in jq: the catalog on stdin, the settings
  # file slurped, the marketplace key read from it by index. Names are
  # compared as JSON strings, so nothing is trimmed from a key.
  local block
  if ! block=$(jq -c --argjson i "$index" --arg src "$catalog_source" --slurpfile s "$SETTINGS" \
    "$JQ_DEFS $JQ_SIMILAR"'
    ($s[0] | mk($i).key) as $k
    | ("@" + $k) as $suf
    | ([.plugins[]? | objects | .name | strings] | unique) as $up
    | [$s[0] | ep | to_entries[] | select(.key | endswith($suf))
        | {name: (.key | .[0:(length - ($suf | length))]), value}] as $pairs
    | ($pairs | map(.name) | unique) as $local
    | ($local - $up) as $orphans
    | ($up - $local) as $new
    | {key: $k, status: "ok", source: $src, skip_reason: "",
       orphans: [$orphans[] as $o | {name: $o, marketplace: $k,
         enabled: ([$pairs[] | select(.name == $o)] | first | .value)}],
       new_upstream: [$new[] | {name: ., marketplace: $k}],
       renames: [$orphans[] as $o | $new[] as $n | select(similar($o; $n))
         | {from: $o, to: $n, marketplace: $k}]}
  ' <<<"$upstream_json"); then
    echo "ERROR: cannot compare marketplace $display_key against its catalog" >&2
    exit 2
  fi
  block="${block%$'\r'}"
  JSON_LINES+="$block"$'\n'

  # --- Render -----------------------------------------------------------------

  local orphan_count new_count local_count upstream_count
  orphan_count=$(jq -j '.orphans | length' <<<"$block")
  new_count=$(jq -j '.new_upstream | length' <<<"$block")
  local_count=$(jq -j --argjson i "$index" "$JQ_DEFS"'mk($i).key as $k | [ep | keys[] | select(endswith("@" + $k))] | length' "$SETTINGS")
  upstream_count=$(jq -j '[.plugins[]? | objects | .name | strings] | unique | length' <<<"$upstream_json")
  ORPHAN_TOTAL=$((ORPHAN_TOTAL + orphan_count))
  NEW_TOTAL=$((NEW_TOTAL + new_count))

  if [[ "$orphan_count" -eq 0 && "$new_count" -eq 0 ]]; then
    printf '  %sOK%s    no drift (%d local, %d upstream)\n' \
      "$GREEN" "$RESET" "$local_count" "$upstream_count"
  fi

  local line enabled entry
  if [[ "$orphan_count" -gt 0 ]]; then
    printf '  %sORPHAN%s  %d entries in the settings file no longer in upstream:\n' \
      "$RED" "$RESET" "$orphan_count"
    # A tab separates the value from the entry; `san` turned any tab in either
    # into `?`, so the split is unambiguous. Only an exact false is a removal
    # candidate; true and every other value are left to a person.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      enabled="${line%%$'\t'*}"
      entry="${line#*$'\t'}"
      local marker="$RED($enabled, manual review required)$RESET"
      [[ "$enabled" == "false" ]] && marker="$YELLOW(false, removal candidate)$RESET"
      printf '    - %-40s %s\n' "$entry" "$marker"
    done < <(jq -r "$JQ_DEFS"'.orphans[] | "\(.enabled | tojson | san)\t\(.name + "@" + .marketplace | san)"' <<<"$block" | display_lines)
  fi

  if [[ "$new_count" -gt 0 ]]; then
    printf '  %sNEW%s     %d upstream plugins with no entry in the settings file (report only):\n' \
      "$CYAN" "$RESET" "$new_count"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '    - %s\n' "$line"
    done < <(jq -r "$JQ_DEFS"'.new_upstream[] | .name + "@" + .marketplace | san' <<<"$block" | display_lines)
  fi

  if jq -e '.renames | length > 0' <<<"$block" >/dev/null; then
    printf '  %sRENAME?%s possible rename pairs (heuristic, review manually):\n' \
      "$YELLOW" "$RESET"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '    - %s\n' "$line"
    done < <(jq -r "$JQ_DEFS"'.renames[] | "\(.from | san) -> \(.to | san)"' <<<"$block" | display_lines)
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
    printf 'Source: live upstream (raw.githubusercontent.com)\n'
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
  if [[ "$ORPHAN_TOTAL" -eq 0 && "$NEW_TOTAL" -eq 0 && "${#SKIPPED_MARKETS[@]}" -eq 0 ]]; then
    printf '  %sOK%s    no drift detected\n' "$GREEN" "$RESET"
  fi
  [[ "$ORPHAN_TOTAL" -gt 0 ]] && printf '  %sDRIFT%s %d orphan entries, run fix-plugin-drift.sh to plan their removal\n' \
    "$RED" "$RESET" "$ORPHAN_TOTAL"
  [[ "$NEW_TOTAL" -gt 0 ]] && printf '  %sNEW%s   %d upstream plugins with no entry in the settings file (report only)\n' \
    "$CYAN" "$RESET" "$NEW_TOTAL"
  [[ "${#SKIPPED_MARKETS[@]}" -gt 0 ]] && printf '  %sSKIP%s  %d marketplaces unreachable: %s\n' \
    "$YELLOW" "$RESET" "${#SKIPPED_MARKETS[@]}" "${SKIPPED_MARKETS[*]}"

  write_findings

  [[ "$ORPHAN_TOTAL" -eq 0 ]] && exit 0
  exit 1
}

main "$@"
