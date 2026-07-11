#!/usr/bin/env bash
# Plugin drift audit for the settings-audit skill (Category E).
#
# Compares .claude/settings.json `enabledPlugins` against live upstream
# `marketplace.json` for each registered marketplace. Detects three drift
# modes that a state-vs-settings bootstrap check misses:
#
#   ORPHAN     — plugin in enabledPlugins, NOT in upstream catalog (deleted upstream)
#   NEW        — plugin in upstream catalog, NOT in enabledPlugins (added upstream)
#   RENAME     — heuristic: ORPHAN + NEW with similar names within one marketplace
#
# Read-only. Network-tolerant: a marketplace whose upstream fetch fails is
# reported SKIP and does not fail the run. Outputs a structured table to
# stdout and a machine-readable JSON to $SETTINGS_AUDIT_OUTPUT_JSON when set (consumed by
# fix-plugin-drift.sh).
#
# Exit codes:
#   0  no drift detected
#   1  drift detected (advisory — invoker decides whether to fix)
#   2  fatal (settings.json missing/invalid, jq/curl missing)
#
# Env overrides (for testing):
#   CLAUDE_SETTINGS_FILE    — path to project settings.json
#   SETTINGS_AUDIT_FIXTURE_DIR — directory of fixture marketplace.json files
#                                 named <marketplace-key>.json. When set,
#                                 the script reads from disk instead of curl.
#   SETTINGS_AUDIT_OUTPUT_JSON                — write structured findings to this path
#   NO_COLOR                   — disable ANSI output

set -uo pipefail

# --- Config resolution -------------------------------------------------------

if [[ -n "${CLAUDE_SETTINGS_FILE:-}" ]]; then
  SETTINGS="$CLAUDE_SETTINGS_FILE"
else
  # Consumer project root: the cwd's git toplevel, then Claude Code's exported
  # project dir, then cwd. Never the plugin's own install directory.
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
  [[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
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

if [[ -z "${SETTINGS_AUDIT_FIXTURE_DIR:-}" ]] && ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl required when SETTINGS_AUDIT_FIXTURE_DIR is unset" >&2
  exit 2
fi

if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "ERROR: settings file is not valid JSON: $SETTINGS" >&2
  exit 2
fi

# --- Output helpers ----------------------------------------------------------

if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
  RED="" YELLOW="" GREEN="" CYAN="" RESET=""
else
  RED=$'\033[31m' YELLOW=$'\033[33m' GREEN=$'\033[32m' CYAN=$'\033[36m' RESET=$'\033[0m'
fi

DRIFT_FOUND=0
SKIPPED_MARKETS=()

# JSON aggregator — built up across marketplaces, flushed at end if requested.
# Each marketplace block: { "key": "...", "status": "ok|skipped", "orphans": [...],
#                           "new_upstream": [...], "renames": [...], "skip_reason": "..." }
JSON_BUFFER='[]'

# --- Levenshtein-ish similarity (simple) -------------------------------------

# Returns 0 if names are similar enough to be likely renames, 1 otherwise.
# Heuristic: same prefix or suffix of >= 4 chars, OR contained substring of >= 5 chars.
# Cheap; no external dependencies. False positives surface as RENAME warnings
# (human reviews) so over-matching is safer than under-matching.
similar_names() {
  local a="$1" b="$2"
  local prefix_a="${a:0:4}" prefix_b="${b:0:4}"
  local suffix_a="${a: -4}" suffix_b="${b: -4}"
  if [[ ${#a} -ge 4 && ${#b} -ge 4 && "$prefix_a" == "$prefix_b" ]]; then return 0; fi
  if [[ ${#a} -ge 4 && ${#b} -ge 4 && "$suffix_a" == "$suffix_b" ]]; then return 0; fi
  if [[ ${#a} -ge 5 && "$b" == *"$a"* ]]; then return 0; fi
  if [[ ${#b} -ge 5 && "$a" == *"$b"* ]]; then return 0; fi
  return 1
}

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

  local url="https://raw.githubusercontent.com/$repo/HEAD/.claude-plugin/marketplace.json"
  curl -fsSL --max-time 15 "$url" 2>/dev/null
}

# --- Per-marketplace audit --------------------------------------------------

# Record a skipped marketplace: print the SKIP line, append to SKIPPED_MARKETS,
# and add a skipped block to JSON_BUFFER. Args: key, suffix, message, json_reason.
record_skip() {
  local market_key="$1" suffix="$2" message="$3" json_reason="$4"
  printf '  %sSKIP%s  %s\n' "$YELLOW" "$RESET" "$message"
  SKIPPED_MARKETS+=("$market_key:$suffix")
  JSON_BUFFER=$(jq --arg k "$market_key" --arg r "$json_reason" \
    '. + [{key:$k, status:"skipped", skip_reason:$r, orphans:[], new_upstream:[], renames:[]}]' \
    <<<"$JSON_BUFFER")
}

audit_marketplace() {
  local market_key="$1"
  local repo
  repo=$(jq -r --arg k "$market_key" '.extraKnownMarketplaces[$k].source.repo // empty' "$SETTINGS" | tr -d '\r')

  printf '\n%s%s%s (%s)\n' "$CYAN" "$market_key" "$RESET" "${repo:-no-repo}"

  if [[ -z "$repo" ]]; then
    record_skip "$market_key" "no-repo" "no source.repo declared" "no source.repo"
    return 0
  fi

  local upstream_json
  if ! upstream_json=$(fetch_upstream "$market_key" "$repo"); then
    record_skip "$market_key" "fetch-failed" \
      "upstream fetch failed (network/404/missing fixture)" "fetch failed"
    return 0
  fi

  if ! jq empty <<<"$upstream_json" 2>/dev/null; then
    record_skip "$market_key" "invalid-json" "upstream returned invalid JSON" "invalid upstream JSON"
    return 0
  fi

  # Upstream plugin name list (sorted, unique). CRLF stripped — GitHub raw
  # responses carry \r\n line endings on Windows curl, breaks comm comparison.
  local upstream_names
  upstream_names=$(jq -r '.plugins[]?.name // empty' <<<"$upstream_json" | tr -d '\r' | sort -u)

  # Local enabled-plugin keys for this marketplace, with values, e.g.
  #   "frontend-design true"
  #   "claude-api false"
  local local_pairs
  local_pairs=$(jq -r --arg suffix "@$market_key" \
    '.enabledPlugins // {} | to_entries[] | select(.key | endswith($suffix)) | "\(.key | rtrimstr($suffix)) \(.value)"' \
    "$SETTINGS" | tr -d '\r' | sort -u)

  local local_names
  local_names=$(awk '{print $1}' <<<"$local_pairs" | sort -u)

  # Compute deltas
  local orphans new_upstream
  orphans=$(comm -23 <(echo "$local_names") <(echo "$upstream_names") | grep -v '^$' || true)
  new_upstream=$(comm -13 <(echo "$local_names") <(echo "$upstream_names") | grep -v '^$' || true)

  local orphan_count new_count
  orphan_count=$(echo "$orphans" | grep -c . || true)
  new_count=$(echo "$new_upstream" | grep -c . || true)

  # Detect possible renames: orphan name similar to a new name
  local renames=""
  if [[ -n "$orphans" && -n "$new_upstream" ]]; then
    local o n
    while IFS= read -r o; do
      [[ -z "$o" ]] && continue
      while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        if similar_names "$o" "$n"; then
          renames+="$o -> $n"$'\n'
        fi
      done <<<"$new_upstream"
    done <<<"$orphans"
  fi

  # --- Render -----------------------------------------------------------------

  if [[ "$orphan_count" -eq 0 && "$new_count" -eq 0 ]]; then
    printf '  %sOK%s    no drift (%d local, %d upstream)\n' \
      "$GREEN" "$RESET" \
      "$(echo "$local_names" | grep -c . || true)" \
      "$(echo "$upstream_names" | grep -c . || true)"
  else
    DRIFT_FOUND=1
  fi

  if [[ "$orphan_count" -gt 0 ]]; then
    printf '  %sORPHAN%s  %d entries in settings.json no longer in upstream:\n' \
      "$RED" "$RESET" "$orphan_count"
    while IFS= read -r o; do
      [[ -z "$o" ]] && continue
      local val
      val=$(awk -v name="$o" '$1 == name {print $2}' <<<"$local_pairs")
      local marker="$YELLOW(false — auto-removable)$RESET"
      [[ "$val" == "true" ]] && marker="$RED(TRUE — manual review required)$RESET"
      printf '    - %-40s %s\n' "$o@$market_key" "$marker"
    done <<<"$orphans"
  fi

  if [[ "$new_count" -gt 0 ]]; then
    printf '  %sNEW%s     %d upstream plugins not in settings.json:\n' \
      "$CYAN" "$RESET" "$new_count"
    while IFS= read -r n; do
      [[ -z "$n" ]] && continue
      printf '    - %s\n' "$n@$market_key"
    done <<<"$new_upstream"
  fi

  if [[ -n "$renames" ]]; then
    printf '  %sRENAME?%s possible rename pairs (heuristic — review manually):\n' \
      "$YELLOW" "$RESET"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      printf '    - %s\n' "$line"
    done <<<"$renames"
  fi

  # --- JSON aggregation -------------------------------------------------------

  local orphans_json new_json renames_json
  # Build a {name: bool} lookup of local enabledPlugins values keyed by plugin
  # name (without @marketplace suffix) so orphan records carry their setting.
  local pairs_obj
  pairs_obj=$(jq -R 'split(" ") | {(.[0]): (.[1] == "true")}' <<<"$local_pairs" | jq -s 'add // {}')

  orphans_json=$(jq -nR --arg k "$market_key" --argjson pairs "$pairs_obj" \
    '[inputs | select(. != "")] | map({name: ., marketplace: $k, enabled: ($pairs[.] // false)})' \
    <<<"$orphans")

  new_json=$(jq -nR --arg k "$market_key" \
    '[inputs | select(. != "")] | map({name: ., marketplace: $k})' <<<"$new_upstream")

  renames_json=$(jq -nR --arg k "$market_key" \
    '[inputs | select(. != "") | split(" -> ") | {from: .[0], to: .[1], marketplace: $k}]' <<<"$renames")

  JSON_BUFFER=$(jq --arg k "$market_key" --argjson o "$orphans_json" --argjson n "$new_json" --argjson r "$renames_json" \
    '. + [{key:$k, status:"ok", skip_reason:"", orphans:$o, new_upstream:$n, renames:$r}]' \
    <<<"$JSON_BUFFER")
}

# --- Main --------------------------------------------------------------------

main() {
  printf '%sPlugin drift audit%s\n' "$CYAN" "$RESET"
  printf 'Settings file: %s\n' "$SETTINGS"
  if [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" ]]; then
    printf 'Source: %sfixtures%s (%s)\n' "$YELLOW" "$RESET" "$SETTINGS_AUDIT_FIXTURE_DIR"
  else
    printf 'Source: live upstream (raw.githubusercontent.com)\n'
  fi

  local marketplace_keys
  marketplace_keys=$(jq -r '.extraKnownMarketplaces // {} | keys[]' "$SETTINGS" | tr -d '\r')

  if [[ -z "$marketplace_keys" ]]; then
    printf '\n%sno marketplaces declared in extraKnownMarketplaces%s\n' "$YELLOW" "$RESET"
    exit 0
  fi

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    audit_marketplace "$key"
  done <<<"$marketplace_keys"

  # Summary
  printf '\n%sSummary%s\n' "$CYAN" "$RESET"
  if [[ "$DRIFT_FOUND" -eq 0 && "${#SKIPPED_MARKETS[@]}" -eq 0 ]]; then
    printf '  %sOK%s    no drift detected\n' "$GREEN" "$RESET"
  else
    [[ "$DRIFT_FOUND" -ne 0 ]] && printf '  %sDRIFT%s detected — run fix-plugin-drift.sh to apply auto-fixes\n' "$RED" "$RESET"
    [[ "${#SKIPPED_MARKETS[@]}" -gt 0 ]] && printf '  %sSKIP%s  %d marketplaces unreachable: %s\n' \
      "$YELLOW" "$RESET" "${#SKIPPED_MARKETS[@]}" "${SKIPPED_MARKETS[*]}"
  fi

  if [[ -n "${SETTINGS_AUDIT_OUTPUT_JSON:-}" ]]; then
    echo "$JSON_BUFFER" | jq '.' >"$SETTINGS_AUDIT_OUTPUT_JSON"
    printf '  JSON written to: %s\n' "$SETTINGS_AUDIT_OUTPUT_JSON"
  fi

  [[ "$DRIFT_FOUND" -eq 0 ]] && exit 0
  exit 1
}

main "$@"
