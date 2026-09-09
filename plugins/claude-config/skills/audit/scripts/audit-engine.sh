#!/usr/bin/env bash
# Deterministic engine for the audit skill.
#
# WHAT IT DECIDES. Every audit row that a script can settle without a reading:
# schema and structure (A), the presence of each baseline permission pattern
# and the placement rules around it (B), MCP server shape (C), hook path, timeout
# shape, matcher class, placeholder quoting and duplicates (D), plugin membership
# and drift (E), the secret scan and path separators (F), the skill-listing
# measurement from an existing debug log (G), model and effort values (H), and
# deep-link registration (I). Each decided row is emitted once, with the surface
# it is about and a stable identity, so the model that runs the audit reads one
# document instead of re-deriving the same facts with a dozen shell calls.
#
# WHAT IT LEAVES TO THE MODEL. Anything that needs a reading: whether a hook
# with no coverage manifest blocks a family, whether a disabled MCP server has a
# documented reason, whether a timeout is reasonable for the tool it wraps,
# whether a custom environment variable is justified, which skill-listing lever
# fits, and every comparison against a live upstream page. Those rows are not
# here, and the model never re-decides a row this engine already settled.
#
# WHAT IT LEAVES BEHIND. A findings document whose rows carry the identity
# tuple the sibling audit-pass skill hashes (check, claim, canonically sorted
# sites of surface plus versioned anchor), so audit-pass can append them
# unchanged and a later run can diff against them. The same identity is what
# the consumer's suppression record keys on, so a finding an operator has
# accepted is reported as suppressed with its reason instead of raised again.
#
# WHAT IT NEVER DOES. It never reads a session-mode signal from the environment
# to decide which rows apply: session posture is declared by the consumer's
# suppression record and nothing else. It never echoes a value from
# settings.local.json other than the four model and effort keys the audit
# already reports by value. It never runs a hook, and it never writes anywhere
# except the path given to --out.
#
# Exit codes:
#   0  no error-severity finding
#   1  at least one error-severity finding
#   2  fatal (jq missing, no readable project settings, bad arguments)
#
# Env overrides (the test seam):
#   SETTINGS_AUDIT_ENGINE_FIXTURE_DIR   project root to audit instead of the git toplevel
#   SETTINGS_AUDIT_ENGINE_USER_DIR      user config dir (else CLAUDE_CONFIG_DIR, else $HOME/.claude)
#   SETTINGS_AUDIT_ENGINE_INSTALLED_JSON path to installed_plugins.json
#   SETTINGS_AUDIT_ENGINE_BASELINE_FILE  required-permissions.md to read the baseline from
#   SETTINGS_AUDIT_ENGINE_DEBUG_DIR     directory of debug logs (else <user dir>/debug)
#   SETTINGS_AUDIT_ENGINE_SKIP_DRIFT    set to 1 to skip the plugin-drift call
#   SETTINGS_AUDIT_FIXTURE_DIR          passed through to check-plugin-drift.sh
#   SETTINGS_AUDIT_MANAGED_PATH         passed through to the managed-scope library
#
# Nearly every jq program below binds --arg variables and reads JSON keys that
# start with a dollar sign; both must reach jq unexpanded, so single quotes are
# the correct spelling throughout and the per-line SC2016 note carries no signal.
# shellcheck disable=SC2016

set -uo pipefail

# Every jq result that re-enters the shell goes through this: on Git for
# Windows jq appends a CR to every stdout line, and an unstripped CR breaks
# every string comparison below.
jqs() { jq "$@" 2>/dev/null | tr -d '\r'; }

usage() {
  cat <<'EOF'
audit-engine.sh — decide every deterministic audit row and emit the result.

Usage:
  audit-engine.sh [--json | --table] [--out <findings.json>] [--docs-dir <dir>]
                  [--debug-log <file>] [--help]
  audit-engine.sh anchor --excerpt <text>
  audit-engine.sh finding-id --check <id> --claim <claim> --site <surface> <anchor> [--site ...]

  --json        emit the full engine document on stdout (default)
  --table       emit a human-readable summary instead
  --out <file>  also write the findings rows, in the audit-pass identity shape, to <file>
  --docs-dir    a directory holding verbatim docs pages (<slug>.md) fetched this run;
                when present the environment-variable rows are checked against env-vars.md
  --debug-log   a debug log to read the skill-listing measurement from, ahead of the
                documented locations

Exit: 0 no error-severity finding; 1 at least one; 2 fatal.
EOF
}

# --- Hashing (the identity contract audit-pass and the suppression record share)

sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -c1-64
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-64
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | sed 's/.*= *//'
  else
    return 1
  fi
}

US=$'\x1f'

# anchor_for_excerpt <text>: the excerpt anchor for a surface with no heading
# concept (a JSON settings file). Normalization is the v1 rule that applies to
# such text: trailing whitespace stripped, internal runs collapsed to one space.
# The duplicate discriminator is the fixed sentinel for a heading-free surface.
anchor_for_excerpt() {
  local norm e n
  norm="$(printf '%s' "$1" | sed -E 's/[[:space:]]+$//; s/[[:space:]]+/ /g')"
  e="$(printf '%s' "$norm" | sha256_hex | cut -c1-12)"
  n="$(printf '\000' | sha256_hex | cut -c1-8)"
  printf 'e:%s:%s' "$e" "$n"
}

# finding_id <check> <claim> <surface> <anchor> [<surface> <anchor> ...]
finding_id() {
  local check="$1" claim="$2"
  shift 2
  local pairs=() s a
  while [[ $# -ge 2 ]]; do
    s="$1"
    a="$2"
    shift 2
    pairs+=("$s$US$a")
  done
  local sorted
  sorted="$(printf '%s\n' "${pairs[@]}" | LC_ALL=C sort)"
  local joined="$check$US$claim"
  while IFS= read -r line; do
    [[ -n "$line" ]] && joined+="$US$line"
  done <<<"$sorted"
  printf '%s' "$joined" | sha256_hex | cut -c1-16
}

# --- Subcommands that expose the identity contract -------------------------

if [[ "${1:-}" == "anchor" ]]; then
  shift
  ex=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --excerpt)
      ex="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
    esac
  done
  [[ -n "$ex" ]] || {
    echo "ERROR: --excerpt required" >&2
    exit 2
  }
  anchor_for_excerpt "$ex"
  printf '\n'
  exit 0
fi

if [[ "${1:-}" == "finding-id" ]]; then
  shift
  check="" claim=""
  sites=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --check)
      check="$2"
      shift 2
      ;;
    --claim)
      claim="$2"
      shift 2
      ;;
    --site)
      sites+=("$2" "$3")
      shift 3
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2
      ;;
    esac
  done
  [[ -n "$check" && -n "$claim" && ${#sites[@]} -ge 2 ]] || {
    echo "ERROR: --check, --claim and at least one --site are required" >&2
    exit 2
  }
  finding_id "$check" "$claim" "${sites[@]}"
  printf '\n'
  exit 0
fi

# --- Arguments ---------------------------------------------------------------

MODE=json
OUT=""
DOCS_DIR=""
DEBUG_LOG_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --json)
    MODE=json
    shift
    ;;
  --table)
    MODE=table
    shift
    ;;
  --out)
    OUT="${2:-}"
    [[ -n "$OUT" ]] || {
      echo "ERROR: --out needs a path" >&2
      exit 2
    }
    shift 2
    ;;
  --docs-dir)
    DOCS_DIR="${2:-}"
    shift 2
    ;;
  --debug-log)
    DEBUG_LOG_ARG="${2:-}"
    shift 2
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
if ! printf '' | sha256_hex >/dev/null 2>&1; then
  echo "ERROR: no SHA-256 tool found (sha256sum, shasum or openssl)" >&2
  exit 2
fi

# --- Roots -------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

if [[ -n "${SETTINGS_AUDIT_ENGINE_FIXTURE_DIR:-}" ]]; then
  PROJECT_ROOT="$SETTINGS_AUDIT_ENGINE_FIXTURE_DIR"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$PROJECT_ROOT" ]] || PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
fi
PROJECT_ROOT="${PROJECT_ROOT//\\//}"
PROJECT_ROOT="${PROJECT_ROOT%/}"

if [[ -n "${SETTINGS_AUDIT_ENGINE_USER_DIR:-}" ]]; then
  USER_DIR="$SETTINGS_AUDIT_ENGINE_USER_DIR"
elif [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  USER_DIR="$CLAUDE_CONFIG_DIR"
elif [[ -n "${HOME:-}" ]]; then
  USER_DIR="$HOME/.claude"
else
  USER_DIR=""
fi

INSTALLED_JSON="${SETTINGS_AUDIT_ENGINE_INSTALLED_JSON:-}"
[[ -z "$INSTALLED_JSON" && -n "$USER_DIR" ]] && INSTALLED_JSON="$USER_DIR/plugins/installed_plugins.json"

BASELINE_FILE="${SETTINGS_AUDIT_ENGINE_BASELINE_FILE:-$PLUGIN_ROOT/skills/audit/reference/required-permissions.md}"

SETTINGS="$PROJECT_ROOT/.claude/settings.json"
LOCAL="$PROJECT_ROOT/.claude/settings.local.json"
MCP="$PROJECT_ROOT/.mcp.json"
USER_SETTINGS=""
[[ -n "$USER_DIR" ]] && USER_SETTINGS="$USER_DIR/settings.json"

# Surfaces are named relative to the project root where they live under it,
# and by their scope label otherwise, so an identity never carries a machine
# path.
SURF_SETTINGS=".claude/settings.json"
SURF_LOCAL=".claude/settings.local.json"
SURF_MCP=".mcp.json"
SURF_USER="user:settings.json"

# --- Rows and findings -------------------------------------------------------

ROWS=()
FINDINGS=()
ERROR_COUNT=0
declare -A SUPPRESS_REASON=()
declare -A SUPPRESS_DATE=()
declare -A SUPPRESS_LAYER=()
SUPPRESSED=()
PERSONAL_ONLY=()
MALFORMED=()

# row <category> <check-slug> <status> <severity> <surface> <claim> <detail> [<excerpt>|-]
#   status: ok | finding | skip | not-inspectable
# A finding row gets an anchor and a finding_id; when the id is in the applied
# suppression set the row is emitted as suppressed instead.
row() {
  local cat="$1" slug="$2" status="$3" sev="$4" surface="$5" claim="$6" detail="$7" excerpt="${8:--}"
  local check="claude-config/audit/$cat/$slug" anchor="" fid="" json
  if [[ "$status" == "finding" ]]; then
    if [[ "$excerpt" == "-" ]]; then
      anchor="s:"
    else
      anchor="$(anchor_for_excerpt "$excerpt")"
    fi
    fid="$(finding_id "$check" "$claim" "$surface" "$anchor")"
    if [[ -n "${SUPPRESS_REASON[$fid]:-}" ]]; then
      json="$(jq -cn --arg cat "$cat" --arg check "$check" --arg st suppressed --arg sev "$sev" \
        --arg surface "$surface" --arg claim "$claim" --arg detail "$detail" --arg anchor "$anchor" \
        --arg fid "$fid" --arg reason "${SUPPRESS_REASON[$fid]}" --arg date "${SUPPRESS_DATE[$fid]}" \
        --arg layer "${SUPPRESS_LAYER[$fid]}" \
        '{category:$cat,check:$check,status:$st,severity:$sev,surface:$surface,claim:$claim,detail:$detail,anchor:$anchor,finding_id:$fid,suppressed:{reason:$reason,date:$date,layer:$layer}}')"
      ROWS+=("$json")
      SUPPRESSED+=("$json")
      return 0
    fi
    [[ "$sev" == "error" ]] && ERROR_COUNT=$((ERROR_COUNT + 1))
    json="$(jq -cn --arg cat "$cat" --arg check "$check" --arg st "$status" --arg sev "$sev" \
      --arg surface "$surface" --arg claim "$claim" --arg detail "$detail" --arg anchor "$anchor" --arg fid "$fid" \
      '{category:$cat,check:$check,status:$st,severity:$sev,surface:$surface,claim:$claim,detail:$detail,anchor:$anchor,finding_id:$fid}')"
    ROWS+=("$json")
    FINDINGS+=("$(jq -cn --arg check "$check" --arg claim "$claim" --arg surface "$surface" --arg anchor "$anchor" \
      --arg fid "$fid" --arg sev "$sev" --arg detail "$detail" --arg cat "$cat" \
      '{finding_id:$fid,identity:{check:$check,claim:$claim,sites:[{surface:$surface,"anchor/v1":$anchor}]},severity:$sev,category:$cat,detail:$detail,lane:"claude-config/audit",tier:"derived"}')")
    return 0
  fi
  json="$(jq -cn --arg cat "$cat" --arg check "$check" --arg st "$status" --arg sev "$sev" \
    --arg surface "$surface" --arg claim "$claim" --arg detail "$detail" \
    '{category:$cat,check:$check,status:$st,severity:$sev,surface:$surface,claim:$claim,detail:$detail}')"
  ROWS+=("$json")
}

# --- Scopes ------------------------------------------------------------------

SCOPES_JSON='[]'
declare -A SCOPE_STATE=()
probe_scope() {
  # probe_scope <label> <path> -> sets SCOPE_STATE[label] to absent|unreadable|invalid|ok
  local label="$1" path="$2" state
  if [[ ! -f "$path" ]]; then
    state=absent
  elif ! : 2>/dev/null <"$path"; then
    state=unreadable
  elif ! tr -d '\r' <"$path" | jq empty 2>/dev/null; then
    state=invalid
  else
    state=ok
  fi
  SCOPE_STATE[$label]="$state"
  SCOPES_JSON="$(jq -c --arg l "$label" --arg p "$path" --arg s "$state" '. + [{label:$l,path:$p,state:$s}]' <<<"$SCOPES_JSON")"
}
probe_scope project "$SETTINGS"
probe_scope local "$LOCAL"
probe_scope mcp "$MCP"
[[ -n "$USER_SETTINGS" ]] && probe_scope user "$USER_SETTINGS"

if [[ "${SCOPE_STATE[project]}" == "absent" ]]; then
  echo "ERROR: no project settings at $SETTINGS" >&2
  exit 2
fi

# jqf <file> <filter> [jq args]: read a JSON scope with CRLF stripped.
jqf() {
  local f="$1"
  shift
  tr -d '\r' <"$f" | jqs "$@"
}

case "${SCOPE_STATE[project]}" in
unreadable)
  row A settings-readable not-inspectable none "$SURF_SETTINGS" scope-unreadable "present but unreadable (sandbox denyRead or filesystem permissions); no row about this file is decidable" -
  ;;
invalid)
  row A settings-valid-json finding error "$SURF_SETTINGS" invalid-json "settings.json is not valid JSON; every other row about it is undecidable" -
  ;;
*) ;;
esac
case "${SCOPE_STATE[local]}" in
unreadable) row A local-readable not-inspectable none "$SURF_LOCAL" scope-unreadable "present but unreadable; reported as not inspectable, never as clean" - ;;
invalid) row A local-valid-json finding error "$SURF_LOCAL" invalid-json "settings.local.json is not valid JSON" - ;;
*) ;;
esac
case "${SCOPE_STATE[mcp]}" in
unreadable) row C mcp-readable not-inspectable none "$SURF_MCP" scope-unreadable "present but unreadable" - ;;
invalid) row C mcp-valid-json finding error "$SURF_MCP" invalid-json ".mcp.json is not valid JSON" - ;;
*) ;;
esac

PROJECT_OK=0
[[ "${SCOPE_STATE[project]}" == "ok" ]] && PROJECT_OK=1
LOCAL_OK=0
[[ "${SCOPE_STATE[local]}" == "ok" ]] && LOCAL_OK=1
USER_OK=0
[[ -n "$USER_SETTINGS" && "${SCOPE_STATE[user]:-absent}" == "ok" ]] && USER_OK=1
MCP_OK=0
[[ "${SCOPE_STATE[mcp]}" == "ok" ]] && MCP_OK=1

# --- Suppression record (.claude/audit-pass.md, three cascade layers) ---------
#
# The record's keys are the finding-suppression convention's. Only the team
# layer suppresses: a personal entry for an id the team layer does not carry is
# reported personal-only, not applied. An entry whose constituents do not hash
# to its own key, or that lacks a required key, is reported malformed and does
# not suppress.

parse_suppressions() {
  # parse_suppressions <file> -> TSV lines: id, check, claim, sites(surface US anchor RS ...), reason, date
  awk '
    BEGIN { infence = 0; inblock = 0; id = ""; RS_SEP = "\x1e"; US_SEP = "\x1f" }
    function strip(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); if (s ~ /^".*"$/) { s = substr(s, 2, length(s) - 2) } else if (s ~ /^\x27.*\x27$/) { s = substr(s, 2, length(s) - 2) } return s }
    function flush() { if (id != "") { printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, check, claim, sites, reason, date } id = ""; check = ""; claim = ""; sites = ""; reason = ""; date = ""; cur_surface = ""; cur_anchor = "" }
    function flush_site() { if (cur_surface != "" || cur_anchor != "") { sites = sites (sites == "" ? "" : RS_SEP) cur_surface US_SEP cur_anchor } cur_surface = ""; cur_anchor = "" }
    /^```/ { if (infence) { flush_site(); flush(); infence = 0; inblock = 0 } else { infence = 1 } next }
    !infence { next }
    /^suppressions:/ { inblock = 1; next }
    !inblock { next }
    /^  [^ ][^:]*:[ \t]*$/ { flush_site(); flush(); id = $0; sub(/^  /, "", id); sub(/:[ \t]*$/, "", id); id = strip(id); next }
    /^    check:/ { v = $0; sub(/^    check:/, "", v); check = strip(v); next }
    /^    claim:/ { v = $0; sub(/^    claim:/, "", v); claim = strip(v); next }
    /^    reason:/ { v = $0; sub(/^    reason:/, "", v); reason = strip(v); next }
    /^    date:/ { v = $0; sub(/^    date:/, "", v); date = strip(v); next }
    /^    sites:/ { next }
    /^      - surface:/ { flush_site(); v = $0; sub(/^      - surface:/, "", v); cur_surface = strip(v); next }
    /^        anchor\/v1:/ { v = $0; sub(/^        anchor\/v1:/, "", v); cur_anchor = strip(v); next }
    END { flush_site(); flush() }
  ' "$1" 2>/dev/null | tr -d '\r'
}

declare -A TEAM_IDS=()
load_suppression_layer() {
  # load_suppression_layer <layer> <file>
  local layer="$1" file="$2" line id check claim sites reason date rec_id
  [[ -f "$file" ]] || return 0
  while IFS=$'\t' read -r id check claim sites reason date; do
    [[ -n "$id" ]] || continue
    if [[ -z "$check" || -z "$claim" || -z "$sites" || -z "$reason" || -z "$date" ]]; then
      MALFORMED+=("$layer:$id missing a required key (check, claim, sites, reason, date)")
      continue
    fi
    local pairs=() site surface anchor
    IFS=$'\x1e' read -r -a sitelist <<<"$sites"
    for site in "${sitelist[@]}"; do
      surface="${site%%$'\x1f'*}"
      anchor="${site#*$'\x1f'}"
      pairs+=("$surface" "$anchor")
    done
    rec_id="$(finding_id "$check" "$claim" "${pairs[@]}")"
    if [[ "$rec_id" != "$id" ]]; then
      MALFORMED+=("$layer:$id constituents hash to $rec_id, not to the key")
      continue
    fi
    case "$layer" in
    team)
      TEAM_IDS[$id]=1
      SUPPRESS_REASON[$id]="$reason"
      SUPPRESS_DATE[$id]="$date"
      SUPPRESS_LAYER[$id]="$layer"
      ;;
    *)
      if [[ -z "${TEAM_IDS[$id]:-}" ]]; then
        PERSONAL_ONLY+=("$layer:$id ($check, $claim) personal-only, not applied")
      fi
      ;;
    esac
  done < <(parse_suppressions "$file")
}
load_suppression_layer team "$PROJECT_ROOT/.claude/audit-pass.md"
[[ -n "$USER_DIR" ]] && load_suppression_layer user-global "$USER_DIR/audit-pass.md"
load_suppression_layer local "$PROJECT_ROOT/.claude/audit-pass.local.md"

# --- Category A: schema and structure ----------------------------------------

SCHEMA_URL="https://json.schemastore.org/claude-code-settings.json"
if [[ $PROJECT_OK -eq 1 ]]; then
  schema="$(jqf "$SETTINGS" -r '."$schema" // empty')"
  if [[ -z "$schema" ]]; then
    row A schema-present finding warning "$SURF_SETTINGS" "missing-key:\$schema" "no \$schema key; editors lose autocomplete and inline validation" '$schema'
  elif [[ "$schema" != "$SCHEMA_URL" ]]; then
    row A schema-url finding warning "$SURF_SETTINGS" "wrong-value:\$schema" "\$schema is $schema, not $SCHEMA_URL" '$schema'
  else
    row A schema-present ok none "$SURF_SETTINGS" "present:\$schema" "\$schema present and pointing at the published schema" -
  fi
  if [[ "$(jqf "$SETTINGS" -r 'has("mcpServers")')" == "true" ]]; then
    row A mcp-in-settings finding error "$SURF_SETTINGS" "misplaced-key:mcpServers" "mcpServers belongs in .mcp.json, not settings.json" /mcpServers
  else
    row A mcp-in-settings ok none "$SURF_SETTINGS" "absent:mcpServers" "no mcpServers key in settings.json" -
  fi
fi
if [[ $LOCAL_OK -eq 1 ]]; then
  if [[ "$(jqf "$LOCAL" -r 'has("mcpServers")')" == "true" ]]; then
    row A mcp-in-local finding error "$SURF_LOCAL" "misplaced-key:mcpServers" "mcpServers belongs in .mcp.json, not settings.local.json" /mcpServers
  fi
  if [[ "$(jqf "$LOCAL" -r 'has("hooks")')" == "true" ]]; then
    row A hooks-in-local finding info "$SURF_LOCAL" "personal-key:hooks" "hooks in settings.local.json are personal, not team configuration" /hooks
  fi
fi

# --- Baseline patterns (read from the reference, never transcribed) ----------

declare -A BASELINE_FAMILY=()
BASELINE_ORDER=()
if [[ -f "$BASELINE_FILE" ]]; then
  while IFS=$'\t' read -r family pattern; do
    [[ -n "$pattern" ]] || continue
    BASELINE_FAMILY[$pattern]="$family"
    BASELINE_ORDER+=("$pattern")
  done < <(awk '
    /^## sensitive-file-deny/ { fam = "sensitive-file-deny"; next }
    /^## destructive-bash-deny/ { fam = "destructive-bash-deny"; next }
    /^## ask-rules/ { fam = "ask-rules"; next }
    /^##/ { fam = "" }
    fam != "" && /^\| `/ {
      line = $0; sub(/^\| `/, "", line); sub(/`.*$/, "", line)
      # Only a permission rule shape counts: a Tool(...) pattern. The section
      # also carries tables of settings keys, which are prose, not baseline.
      if (line ~ /^[A-Za-z]+\(.*\)$/) printf "%s\t%s\n", fam, line
    }
  ' "$BASELINE_FILE" | tr -d '\r')
else
  row B baseline-reference skip none "$SURF_SETTINGS" "reference-missing" "required-permissions.md not found at $BASELINE_FILE; baseline presence not decided" -
fi

# --- Hook inventory (delegated to check-hook-coverage.sh) ---------------------

INVENTORY_JSON='{"inventory":"none","hooks":[],"plugins":[],"levers":[],"unreadable":[],"divergence":[]}'
INVENTORY_EXIT=2
if [[ -x "$SCRIPT_DIR/check-hook-coverage.sh" || -f "$SCRIPT_DIR/check-hook-coverage.sh" ]]; then
  inv_out="$(HOOK_COVERAGE_FIXTURE_DIR="$PROJECT_ROOT" HOOK_COVERAGE_USER_DIR="$USER_DIR" \
    HOOK_COVERAGE_INSTALLED_JSON="$INSTALLED_JSON" HOOK_COVERAGE_MANAGED_JSON="${SETTINGS_AUDIT_MANAGED_PATH:-}" \
    bash "$SCRIPT_DIR/check-hook-coverage.sh" --json 2>/dev/null)"
  INVENTORY_EXIT=$?
  if [[ $INVENTORY_EXIT -ne 2 ]] && jq empty <<<"$inv_out" 2>/dev/null; then
    INVENTORY_JSON="$(tr -d '\r' <<<"$inv_out")"
  fi
fi
INVENTORY_STATE="$(jqs -r '.inventory // "none"' <<<"$INVENTORY_JSON")"

# Lever reading: a hook one of these has switched off is not coverage.
LEVER_DISABLE_ALL="$(jqs -r '[.levers[]? | select(.key=="disableAllHooks" and .value=="true")] | length' <<<"$INVENTORY_JSON")"
LEVER_MANAGED="$(jqs -r '[.levers[]? | select((.key=="allowManagedHooksOnly" or .key=="strictPluginOnlyCustomization") and .value=="true")] | length' <<<"$INVENTORY_JSON")"
HOOKS_LIVE=1
[[ "${LEVER_DISABLE_ALL:-0}" != "0" || "${LEVER_MANAGED:-0}" != "0" ]] && HOOKS_LIVE=0

# --- Coverage manifests (hooks/coverage.json shipped by an enabled plugin) ----

declare -A COVERED_BY=()
COVERAGE_JSON='[]'
while IFS=$'\t' read -r pkey pstatus ppath; do
  [[ -n "$pkey" && "$pstatus" == "OK" && -n "$ppath" ]] || continue
  ppath="${ppath//\\//}"
  manifest="$ppath/hooks/coverage.json"
  [[ -f "$manifest" ]] || continue
  if ! jq empty "$manifest" 2>/dev/null; then
    row D coverage-manifest finding warning "plugin:$pkey" "invalid-json:hooks/coverage.json" "coverage manifest is not valid JSON; no narrowing taken from it" hooks/coverage.json
    continue
  fi
  entries="$(jqs -c --arg p "$pkey" '(.coverage // [])[] | select(.event=="PreToolUse" and (.decision // "block")=="block") | {plugin:$p,hook:.hook,matcher:(.matcher // ""),patterns:(.patterns // []),levers:(.levers // [])}' "$manifest")"
  [[ -n "$entries" ]] || continue
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    COVERAGE_JSON="$(jq -c --argjson e "$entry" '. + [$e]' <<<"$COVERAGE_JSON")"
    while IFS= read -r pat; do
      [[ -n "$pat" ]] || continue
      # The tool surface the pattern defends must be on the matcher: a Read
      # pattern is never covered by a Bash hook.
      tool="${pat%%(*}"
      matcher="$(jqs -r '.matcher' <<<"$entry")"
      case "|$matcher|" in
      *"|$tool|"*) ;;
      *"*"*) ;;
      *) continue ;;
      esac
      levers="$(jqs -r '[.levers[]? | .name] | join(", ")' <<<"$entry")"
      hook="$(jqs -r '.hook' <<<"$entry")"
      COVERED_BY[$pat]="$pkey $hook (levers: ${levers:-none})"
    done < <(jqs -r '.patterns[]?' <<<"$entry")
  done <<<"$entries"
done < <(jqs -r '.plugins[]? | [.plugin, .status, (.path // "")] | @tsv' <<<"$INVENTORY_JSON")

# --- Category B: permissions -------------------------------------------------

if [[ $PROJECT_OK -eq 1 && ${#BASELINE_ORDER[@]} -gt 0 ]]; then
  deny_json="$(jqf "$SETTINGS" -c '(.permissions.deny // [])')"
  ask_json="$(jqf "$SETTINGS" -c '(.permissions.ask // [])')"
  allow_json="$(jqf "$SETTINGS" -c '(.permissions.allow // [])')"
  for pat in "${BASELINE_ORDER[@]}"; do
    fam="${BASELINE_FAMILY[$pat]}"
    case "$fam" in
    ask-rules)
      target="ask"
      list="$ask_json"
      sev=warning
      ;;
    *)
      target="deny"
      list="$deny_json"
      sev=error
      ;;
    esac
    present="$(jq -r --arg p "$pat" 'index($p) != null' <<<"$list")"
    if [[ "$present" == "true" ]]; then
      row B "baseline-$fam" ok none "$SURF_SETTINGS" "present-pattern:$pat" "$target carries $pat" -
      continue
    fi
    if [[ -n "${COVERED_BY[$pat]:-}" ]]; then
      if [[ $HOOKS_LIVE -eq 1 ]]; then
        row B "baseline-$fam" finding info "$SURF_SETTINGS" "missing-pattern:$pat" "not in permissions.$target; a live PreToolUse hook already blocks it: ${COVERED_BY[$pat]}. Coverage ends if that plugin is disabled or its levers narrow it" "/permissions/$target"
      else
        row B "baseline-$fam" finding "$sev" "$SURF_SETTINGS" "missing-pattern:$pat" "not in permissions.$target; a hook declares coverage (${COVERED_BY[$pat]}) but a suppression lever is set, so the hook is not live" "/permissions/$target"
      fi
      continue
    fi
    row B "baseline-$fam" finding "$sev" "$SURF_SETTINGS" "missing-pattern:$pat" "not in permissions.$target and no coverage manifest names it; narrowings 1 and 2 (a documented exemption or hook convention) are the model's to check" "/permissions/$target"
  done
  # Broad allow entries and the completeness rows, both informational.
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    case "$a" in
    "Bash(git *)" | "Bash(git:*)")
      row B broad-allow finding warning "$SURF_SETTINGS" "broad-allow:$a" "a blanket git allow; split it into the operations the workflow needs" /permissions/allow
      ;;
    *) ;;
    esac
  done < <(jq -r '.[]' <<<"$allow_json")
  for want in "git commit" "git fetch" "git stash"; do
    if jq -e --arg w "$want" '[.[] | select(startswith("Bash(" + $w))] | length > 0' <<<"$allow_json" >/dev/null; then
      row B allow-completeness ok none "$SURF_SETTINGS" "present-allow:$want" "an allow rule for $want exists" -
    else
      row B allow-completeness finding info "$SURF_SETTINGS" "missing-allow:$want" "no allow rule for $want; under auto mode the classifier decides it, so this is a convenience, never a gap" /permissions/allow
    fi
  done
fi
if [[ $LOCAL_OK -eq 1 ]]; then
  local_deny="$(jqf "$LOCAL" -r '(.permissions.deny // []) | length')"
  if [[ "${local_deny:-0}" != "0" ]]; then
    row B deny-in-local finding error "$SURF_LOCAL" "misplaced-rules:permissions.deny" "$local_deny deny rule(s) in settings.local.json, where they are ignored; move them to settings.json" /permissions/deny
  else
    row B deny-in-local ok none "$SURF_LOCAL" "absent:permissions.deny" "no deny rules in settings.local.json" -
  fi
fi

# --- Category C: MCP servers -------------------------------------------------

if [[ $MCP_OK -eq 1 ]]; then
  servers="$(jqf "$MCP" -r '.mcpServers // {} | keys[]')"
  while IFS= read -r srv; do
    [[ -n "$srv" ]] || continue
    stype="$(jqf "$MCP" -r --arg s "$srv" '.mcpServers[$s].type // "stdio"')"
    if [[ "$stype" == "stdio" ]]; then
      cmd="$(jqf "$MCP" -r --arg s "$srv" '.mcpServers[$s].command // empty')"
      if [[ -z "$cmd" ]]; then
        row C server-command finding error "$SURF_MCP" "missing-command:$srv" "stdio server $srv declares no command" "/mcpServers/$srv/command"
      elif [[ "$cmd" == /* || "$cmd" == ./* || "$cmd" == ../* ]]; then
        if [[ -f "$cmd" || -f "$PROJECT_ROOT/$cmd" ]]; then
          row C server-command ok none "$SURF_MCP" "command-resolves:$srv" "$cmd exists" -
        else
          row C server-command finding error "$SURF_MCP" "command-missing:$srv" "$cmd does not exist" "/mcpServers/$srv/command"
        fi
      elif command -v "$cmd" >/dev/null 2>&1; then
        row C server-command ok none "$SURF_MCP" "command-resolves:$srv" "$cmd is on PATH" -
      else
        row C server-command finding error "$SURF_MCP" "command-missing:$srv" "$cmd is not on PATH here" "/mcpServers/$srv/command"
      fi
    else
      url="$(jqf "$MCP" -r --arg s "$srv" '.mcpServers[$s].url // empty')"
      if [[ "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        row C server-url ok none "$SURF_MCP" "url-wellformed:$srv" "$url" -
      else
        row C server-url finding warning "$SURF_MCP" "url-malformed:$srv" "${url:-<no url>} is not a well-formed http(s) URL" "/mcpServers/$srv/url"
      fi
    fi
    bare="$(jqf "$MCP" -r --arg s "$srv" '(.mcpServers[$s].env // {}) | to_entries[] | select(.value | tostring | test("\\$[A-Za-z_]")) | .key')"
    while IFS= read -r ek; do
      [[ -n "$ek" ]] || continue
      row C env-syntax finding warning "$SURF_MCP" "bare-env-reference:$srv:$ek" "env $ek uses a bare \$VAR; .mcp.json expands \${VAR} only" "/mcpServers/$srv/env/$ek"
    done <<<"$bare"
  done <<<"$servers"
  if [[ $PROJECT_OK -eq 1 ]]; then
    if [[ "$(jqf "$SETTINGS" -r '.enableAllProjectMcpServers // false')" == "true" ]]; then
      row C enable-all finding error "$SURF_SETTINGS" "enableAllProjectMcpServers:true" "every .mcp.json server is auto-approved; use the enabled/disabled allowlists instead" /enableAllProjectMcpServers
    fi
    uncovered="$(comm -23 <(printf '%s\n' "$servers" | sort) <(jqf "$SETTINGS" -r '((.enabledMcpjsonServers // []) + (.disabledMcpjsonServers // []))[]' | sort) | grep -v '^$' || true)"
    while IFS= read -r u; do
      [[ -n "$u" ]] || continue
      row C server-coverage finding error "$SURF_SETTINGS" "unlisted-server:$u" "$u is in .mcp.json but in neither enabledMcpjsonServers nor disabledMcpjsonServers" /enabledMcpjsonServers
    done <<<"$uncovered"
    unknown="$(comm -13 <(printf '%s\n' "$servers" | sort) <(jqf "$SETTINGS" -r '((.enabledMcpjsonServers // []) + (.disabledMcpjsonServers // []))[]' | sort) | grep -v '^$' || true)"
    while IFS= read -r u; do
      [[ -n "$u" ]] || continue
      row C server-names finding error "$SURF_SETTINGS" "unknown-server:$u" "$u is listed in settings.json but is not a server in .mcp.json" /disabledMcpjsonServers
    done <<<"$unknown"
  fi
fi

# --- Category D: hooks ---------------------------------------------------------

resolve_hook_path() {
  # resolve_hook_path <source> <command> <plugin-path> -> the first token with placeholders expanded
  local src="$1" cmd="$2" ppath="$3" first
  first="$(printf '%s' "$cmd" | awk '{print $1}')"
  # Shell-form hooks quote the placeholder, "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh,
  # so the quotes sit inside the token; the shell would remove them all.
  first="${first//\"/}"
  first="${first//\$\{CLAUDE_PROJECT_DIR\}/$PROJECT_ROOT}"
  first="${first//\$CLAUDE_PROJECT_DIR/$PROJECT_ROOT}"
  if [[ -n "$ppath" ]]; then
    first="${first//\$\{CLAUDE_PLUGIN_ROOT\}/$ppath}"
    first="${first//\$CLAUDE_PLUGIN_ROOT/$ppath}"
  fi
  printf '%s' "$first"
}

declare -A HOOK_SEEN=()
declare -A MATCHER_SEEN=()
declare -A PLUGIN_PATH=()
while IFS=$'\t' read -r pkey pstatus ppath; do
  [[ -n "$pkey" ]] || continue
  PLUGIN_PATH["plugin:$pkey"]="${ppath//\\//}"
done < <(jqs -r '.plugins[]? | [.plugin, .status, (.path // "")] | @tsv' <<<"$INVENTORY_JSON")

while IFS=$'\t' read -r src event matcher cmd timeout htype hif hargs; do
  [[ -n "$src" ]] || continue
  surface="$src"
  [[ "$src" == "settings:project" ]] && surface="$SURF_SETTINGS"
  [[ "$src" == "settings:local" ]] && surface="$SURF_LOCAL"
  [[ "$src" == "settings:user" ]] && surface="$SURF_USER"
  key="$src|$event|$matcher|$cmd|$hif"
  if [[ -n "${HOOK_SEEN[$key]:-}" ]]; then
    row D duplicate-hook finding info "$surface" "duplicate-hook:$event:$matcher:$cmd" "the same command is registered twice for $event/$matcher" "$event/$matcher/$cmd"
  fi
  HOOK_SEEN[$key]=1
  [[ "$htype" == "command" || -z "$htype" ]] || continue
  # Timeout shape: a round thousands multiple reads as milliseconds.
  if [[ -n "$timeout" && "$timeout" =~ ^[0-9]+$ && $timeout -ge 1000 && $((timeout % 1000)) -eq 0 ]]; then
    row D timeout-unit finding warning "$surface" "millisecond-timeout:$event:$cmd" "timeout $timeout reads as milliseconds; the field is seconds" "$event/$matcher/$cmd"
  fi
  # Matcher class: only letters, digits, _ - space , | is an exact-string list.
  # One row per matcher, not per command under it.
  mkey="$src|$event|$matcher"
  if [[ -z "${MATCHER_SEEN[$mkey]:-}" && -n "$matcher" && "$matcher" != "*" && ! "$matcher" =~ ^[A-Za-z0-9_\ ,|-]+$ ]]; then
    MATCHER_SEEN[$mkey]=1
    if [[ ! "$matcher" =~ ^\^.*\$$ ]]; then
      row D matcher-anchoring finding warning "$surface" "unanchored-regex-matcher:$event:$matcher" "matcher $matcher is a regex and is not anchored with ^...\$, so it also matches longer tool names" "$event/$matcher"
    fi
  fi
  # Shell form (no args) with an unquoted placeholder.
  if [[ "$hargs" == "[]" || -z "$hargs" ]]; then
    if printf '%s' "$cmd" | grep -Eq '(^|[^"])\$(\{CLAUDE_(PROJECT_DIR|PLUGIN_ROOT|PLUGIN_DATA)\}|CLAUDE_(PROJECT_DIR|PLUGIN_ROOT|PLUGIN_DATA))'; then
      row D placeholder-quoting finding warning "$surface" "unquoted-placeholder:$event:$cmd" "a path placeholder in shell form is not wrapped in double quotes; a space in the path breaks the hook" "$event/$matcher/$cmd"
    fi
  fi
  # Path resolution for the first token when it is a path.
  ppath="${PLUGIN_PATH[$src]:-}"
  first="$(resolve_hook_path "$src" "$cmd" "$ppath")"
  case "$first" in
  */*)
    if [[ "$first" == *'$'* ]]; then
      row D hook-path skip none "$surface" "unexpanded-placeholder:$cmd" "first token still carries a placeholder this engine cannot expand; the model resolves it" -
    elif [[ ! -e "$first" ]]; then
      row D hook-path finding error "$surface" "hook-path-missing:$event:$cmd" "$first does not exist" "$event/$matcher/$cmd"
    elif [[ ! -r "$first" ]]; then
      row D hook-path finding error "$surface" "hook-path-unreadable:$event:$cmd" "$first is not readable" "$event/$matcher/$cmd"
    else
      row D hook-path ok none "$surface" "hook-path-resolves:$event:$cmd" "$first exists and is readable" -
    fi
    ;;
  *) ;;
  esac
done < <(jqs -r '.hooks[]? | [.source, .event, .matcher, .command, ((.timeout // "") | tostring), (.type // "command"), (.if // ""), ((.args // []) | tojson)] | @tsv' <<<"$INVENTORY_JSON")

# Lever state is reported, never judged.
for lever in disableAllHooks allowManagedHooksOnly strictPluginOnlyCustomization; do
  lv="$(jqs -r --arg k "$lever" '[.levers[]? | select(.key==$k)] | map("\(.scope)=\(.value)") | join(", ")' <<<"$INVENTORY_JSON")"
  if [[ -n "$lv" ]]; then
    row D hook-levers ok none "settings" "lever-set:$lever" "$lever set: $lv (every hook it switches off is not coverage)" -
  else
    row D hook-levers ok none "settings" "lever-unset:$lever" "$lever unset in every scope read" -
  fi
done
case "$INVENTORY_STATE" in
complete) row D hook-inventory ok none "settings" "inventory:complete" "every enabled plugin resolved and every hook source parsed" - ;;
partial) row D hook-inventory skip none "settings" "inventory:partial" "some plugin or hook config could not be read; families those could cover stay conditional" - ;;
*) row D hook-inventory skip none "settings" "inventory:none" "no hook inventory was taken" - ;;
esac
# One row per marketplace, not per plugin: on a directory-source marketplace
# every plugin diverges the same way, and one finding says it.
while IFS=$'\t' read -r mk count example_loaded example_cached; do
  [[ -n "$mk" ]] || continue
  row E cache-divergence finding info "marketplace:$mk" "cache-vs-loaded:$mk" "$count plugin(s) from $mk load from the marketplace directory (for example $example_loaded) while the registry cache holds an older snapshot (for example $example_cached); a tool resolving through the registry reads the snapshot, the session does not" "$mk"
done < <(jqs -r '[.divergence[]? | . + {mk: (.plugin | split("@") | .[1] // "")}] | group_by(.mk) | .[] | [.[0].mk, (length|tostring), .[0].loaded, .[0].cached] | @tsv' <<<"$INVENTORY_JSON")

# --- Category E: plugins -------------------------------------------------------

known_markets="$(
  {
    [[ $PROJECT_OK -eq 1 ]] && jqf "$SETTINGS" -r '.extraKnownMarketplaces // {} | keys[]'
    [[ $LOCAL_OK -eq 1 ]] && jqf "$LOCAL" -r '.extraKnownMarketplaces // {} | keys[]'
    [[ $USER_OK -eq 1 ]] && jqf "$USER_SETTINGS" -r '.extraKnownMarketplaces // {} | keys[]'
    [[ -n "$USER_DIR" && -f "$USER_DIR/plugins/known_marketplaces.json" ]] && jqs -r 'keys[]' "$USER_DIR/plugins/known_marketplaces.json"
  } | sort -u
)"
check_plugin_keys() {
  # check_plugin_keys <file> <surface>
  local file="$1" surface="$2"
  while IFS=$'\t' read -r pk pv; do
    [[ -n "$pk" ]] || continue
    market="${pk##*@}"
    if ! grep -qx -- "$market" <<<"$known_markets"; then
      row E marketplace-known finding error "$surface" "unknown-marketplace:$pk" "$pk names marketplace $market, which no scope registers" "/enabledPlugins/$pk"
    fi
    if [[ "$pv" == "false" ]]; then
      row E disabled-plugin finding info "$surface" "disabled-plugin:$pk" "$pk is explicitly disabled; confirm the opt-out is intentional and recorded" "/enabledPlugins/$pk"
    fi
  done < <(jqf "$file" -r '(.enabledPlugins // {}) | to_entries[] | [.key, (.value|tostring)] | @tsv')
}
[[ $PROJECT_OK -eq 1 ]] && check_plugin_keys "$SETTINGS" "$SURF_SETTINGS"
[[ $LOCAL_OK -eq 1 ]] && check_plugin_keys "$LOCAL" "$SURF_LOCAL"

DRIFT_JSON='[]'
DRIFT_STATE=skipped
if [[ "${SETTINGS_AUDIT_ENGINE_SKIP_DRIFT:-0}" != "1" && $PROJECT_OK -eq 1 && -f "$SCRIPT_DIR/check-plugin-drift.sh" ]]; then
  if command -v curl >/dev/null 2>&1 || [[ -n "${SETTINGS_AUDIT_FIXTURE_DIR:-}" ]]; then
    drift_tmp="$(mktemp)"
    NO_COLOR=1 CLAUDE_SETTINGS_FILE="$SETTINGS" SETTINGS_AUDIT_OUTPUT_JSON="$drift_tmp" \
      bash "$SCRIPT_DIR/check-plugin-drift.sh" >/dev/null 2>&1
    if [[ -s "$drift_tmp" ]] && jq empty "$drift_tmp" 2>/dev/null; then
      DRIFT_JSON="$(tr -d '\r' <"$drift_tmp")"
      DRIFT_STATE=ran
    fi
    rm -f "$drift_tmp"
  fi
fi
if [[ "$DRIFT_STATE" == "ran" ]]; then
  while IFS=$'\t' read -r mk st reason; do
    [[ -n "$mk" ]] || continue
    [[ "$st" == "skipped" ]] && row E drift skip none "$SURF_SETTINGS" "drift-skipped:$mk" "marketplace $mk not diffed: $reason" -
  done < <(jqs -r '.[] | [.key, .status, (.skip_reason // "")] | @tsv' <<<"$DRIFT_JSON")
  while IFS=$'\t' read -r name mk enabled; do
    [[ -n "$name" ]] || continue
    if [[ "$enabled" == "true" ]]; then
      row E drift-orphan finding warning "$SURF_SETTINGS" "orphan-enabled:$name@$mk" "$name@$mk is enabled but no longer in the $mk catalog; review before removing" "/enabledPlugins/$name@$mk"
    else
      row E drift-orphan finding info "$SURF_SETTINGS" "orphan-disabled:$name@$mk" "$name@$mk is disabled and gone from the $mk catalog; the entry is removable" "/enabledPlugins/$name@$mk"
    fi
  done < <(jqs -r '.[] | .orphans[]? | [.name, .marketplace, (.enabled|tostring)] | @tsv' <<<"$DRIFT_JSON")
  # The drift script reads the project file alone; Claude Code merges the user,
  # project and local scopes, so a catalog entry keyed in any of them is not
  # new to the session. Only a key absent from every readable scope is reported.
  merged_keys="$(
    {
      [[ $PROJECT_OK -eq 1 ]] && jqf "$SETTINGS" -r '(.enabledPlugins // {}) | keys[]'
      [[ $LOCAL_OK -eq 1 ]] && jqf "$LOCAL" -r '(.enabledPlugins // {}) | keys[]'
      [[ $USER_OK -eq 1 ]] && jqf "$USER_SETTINGS" -r '(.enabledPlugins // {}) | keys[]'
    } | sort -u
  )"
  while IFS=$'\t' read -r name mk; do
    [[ -n "$name" ]] || continue
    grep -qx -- "$name@$mk" <<<"$merged_keys" && continue
    row E drift-new finding info "$SURF_SETTINGS" "new-upstream:$name@$mk" "$name@$mk is in the $mk catalog and has no enabledPlugins entry in any scope; record an explicit true or false" "/enabledPlugins/$name@$mk"
  done < <(jqs -r '.[] | .new_upstream[]? | [.name, .marketplace] | @tsv' <<<"$DRIFT_JSON")
  while IFS=$'\t' read -r from to mk; do
    [[ -n "$from" ]] || continue
    row E drift-rename finding warning "$SURF_SETTINGS" "possible-rename:$from->$to@$mk" "$from may have been renamed to $to in $mk; confirm before editing the key" "/enabledPlugins/$from@$mk"
  done < <(jqs -r '.[] | .renames[]? | [.from, .to, .marketplace] | @tsv' <<<"$DRIFT_JSON")
else
  row E drift skip none "$SURF_SETTINGS" "drift-not-run" "plugin drift not computed (curl absent, skipped, or no project settings)" -
fi

# --- Category F: environment variables -----------------------------------------

SECRET_RE='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{5,}|sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|xox[abp]-[A-Za-z0-9-]{10,}'
if [[ $PROJECT_OK -eq 1 ]]; then
  if tr -d '\r' <"$SETTINGS" | grep -Eq "$SECRET_RE"; then
    row F secrets finding error "$SURF_SETTINGS" "secret-shaped-value" "a token-shaped value is present in the tracked settings file; move it to settings.local.json or a credential store" /env
  else
    row F secrets ok none "$SURF_SETTINGS" "no-secret-shaped-value" "no token-shaped value in settings.json" -
  fi
  while IFS=$'\t' read -r ek ev; do
    [[ -n "$ek" ]] || continue
    if [[ "$ev" == *\\* ]]; then
      row F path-separators finding info "$SURF_SETTINGS" "backslash-path:$ek" "env $ek carries a backslash path; forward slashes work on every platform" "/env/$ek"
    fi
    if [[ -n "$DOCS_DIR" && -f "$DOCS_DIR/env-vars.md" ]]; then
      if grep -q -- "\`$ek\`" "$DOCS_DIR/env-vars.md"; then
        row F documented-var ok none "$SURF_SETTINGS" "documented-on-env-vars:$ek" "$ek is documented on env-vars" -
      else
        row F documented-var finding info "$SURF_SETTINGS" "not-on-env-vars-page:$ek" "$ek is not on the env-vars page; it may be documented elsewhere or be a justified custom variable (the model decides)" "/env/$ek"
      fi
    else
      row F documented-var skip none "$SURF_SETTINGS" "env-page-not-fetched:$ek" "env-vars.md not in --docs-dir; documentation status of $ek not decided" -
    fi
  done < <(jqf "$SETTINGS" -r '(.env // {}) | to_entries[] | [.key, (.value|tostring)] | @tsv')
fi

# --- Category G: skill-listing measurement from an existing debug log ----------

DEBUG_LOG=""
if [[ -n "$DEBUG_LOG_ARG" && -f "$DEBUG_LOG_ARG" ]]; then
  DEBUG_LOG="$DEBUG_LOG_ARG"
elif [[ -n "${CLAUDE_CODE_DEBUG_LOGS_DIR:-}" && -f "${CLAUDE_CODE_DEBUG_LOGS_DIR}" ]]; then
  DEBUG_LOG="$CLAUDE_CODE_DEBUG_LOGS_DIR"
else
  debug_dir="${SETTINGS_AUDIT_ENGINE_DEBUG_DIR:-}"
  [[ -z "$debug_dir" && -n "$USER_DIR" ]] && debug_dir="$USER_DIR/debug"
  if [[ -d "$debug_dir" ]]; then
    # Newest .txt by modification time; find plus sort keeps odd filenames safe.
    DEBUG_LOG="$(find "$debug_dir" -maxdepth 1 -name '*.txt' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2- || true)"
    if [[ -z "$DEBUG_LOG" ]]; then
      # BSD find has no -printf; fall back to the shell's own ordering by mtime.
      newest=""
      for f in "$debug_dir"/*.txt; do
        [[ -f "$f" ]] || continue
        if [[ -z "$newest" || "$f" -nt "$newest" ]]; then newest="$f"; fi
      done
      DEBUG_LOG="$newest"
    fi
  fi
fi
G_JSON='{"measured":false}'
if [[ -n "$DEBUG_LOG" ]]; then
  gline="$(grep -E 'Skill listing over budget: [0-9]+ skills, [0-9]+ chars > [0-9]+ budget' "$DEBUG_LOG" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$gline" ]]; then
    g_skills="$(sed -E 's/.*over budget: ([0-9]+) skills.*/\1/' <<<"$gline")"
    g_chars="$(sed -E 's/.*skills, ([0-9]+) chars.*/\1/' <<<"$gline")"
    g_budget="$(sed -E 's/.*chars > ([0-9]+) budget.*/\1/' <<<"$gline")"
    G_JSON="$(jq -cn --arg log "$DEBUG_LOG" --argjson s "$g_skills" --argjson c "$g_chars" --argjson b "$g_budget" \
      '{measured:true,route:"debug-log",log:$log,skills:$s,chars:$c,budget:$b,over_by:($c-$b),overflow:true}')"
    row G listing-budget finding warning "settings" "listing-over-budget" "debug log $DEBUG_LOG: $g_skills skills, $g_chars chars against a $g_budget budget, over by $((g_chars - g_budget)); descriptions of the least-used skills are cut" "skill-listing"
  else
    G_JSON="$(jq -cn --arg log "$DEBUG_LOG" '{measured:true,route:"debug-log",log:$log,overflow:false}')"
    row G listing-budget ok none "settings" "listing-fits" "debug log $DEBUG_LOG carries no over-budget warning; the listing fit its budget in that session" -
  fi
else
  row G listing-budget skip none "settings" "listing-not-measured" "no debug log found (--debug-log, CLAUDE_CODE_DEBUG_LOGS_DIR, or <user dir>/debug/*.txt); measure with /doctor interactively or a --debug relaunch, never report clean" -
fi

# --- Category H: model and effort values -----------------------------------------

check_h() {
  # check_h <file> <surface>
  local file="$1" surface="$2"
  local effort raw dedup mix enforce avail_len
  effort="$(jqf "$file" -r 'if has("effortLevel") then (.effortLevel|tostring) else "" end')"
  case "$effort" in
  max | ultracode)
    row H effort-level finding warning "$surface" "effortLevel:$effort" "effortLevel $effort is session-only and is not accepted from a settings file; the persisted level is not the one asked for" /effortLevel
    ;;
  *) ;;
  esac
  if [[ "$(jqf "$file" -r 'has("fallbackModel")')" == "true" ]]; then
    raw="$(jqf "$file" -r '.fallbackModel | if type=="array" then length else 1 end')"
    dedup="$(jqf "$file" -r '.fallbackModel | if type=="array" then (reduce .[] as $m ([]; if index($m) then . else . + [$m] end) | length) else 1 end')"
    if [[ "$raw" -gt 3 ]]; then
      row H fallback-chain finding warning "$surface" "fallbackModel-raw-length:$raw" "fallbackModel has $raw entries; the declared schema caps the array at 3" /fallbackModel
    fi
    if [[ "$dedup" -gt 3 ]]; then
      row H fallback-chain finding warning "$surface" "fallbackModel-dedup-length:$dedup" "fallbackModel keeps $dedup distinct entries; the chain is capped at 3 after duplicate removal, so later entries may be ignored" /fallbackModel
    fi
  fi
  if [[ "$(jqf "$file" -r 'has("availableModels")')" == "true" ]]; then
    mix="$(jqf "$file" -r '.availableModels | if type=="array" then . else [] end | map(tostring) | . as $l | [ $l[] | select(test("^(opus|sonnet|haiku|fable)$")) ] as $fams | [ $fams[] | . as $f | select(any($l[]; . != $f and (ascii_downcase | contains($f)))) ] | join(",")')"
    if [[ -n "$mix" ]]; then
      row H available-models finding warning "$surface" "availableModels-wildcard-mix:$mix" "a family wildcard ($mix) sits beside a specific model of the same family; the specific entry disables the wildcard" /availableModels
    fi
    avail_len="$(jqf "$file" -r '.availableModels | if type=="array" then length else 0 end')"
  else
    avail_len=0
  fi
  enforce="$(jqf "$file" -r 'if has("enforceAvailableModels") then (.enforceAvailableModels|tostring) else "" end')"
  if [[ "$enforce" == "true" && "${avail_len:-0}" -eq 0 ]]; then
    row H enforce-available finding error "$surface" "enforceAvailableModels-without-list" "enforceAvailableModels is true with no availableModels; the flag has no effect, so the Default option is not constrained" /enforceAvailableModels
  fi
}
[[ $PROJECT_OK -eq 1 ]] && check_h "$SETTINGS" "$SURF_SETTINGS"
[[ $LOCAL_OK -eq 1 ]] && check_h "$LOCAL" "$SURF_LOCAL"
[[ $USER_OK -eq 1 ]] && check_h "$USER_SETTINGS" "$SURF_USER"

# --- Category I: deep-link registration ------------------------------------------

check_i() {
  local file="$1" surface="$2" v
  if [[ "$(jqf "$file" -r 'has("disableDeepLinkRegistration")')" == "true" ]]; then
    v="$(jqf "$file" -r '.disableDeepLinkRegistration | tostring')"
    if [[ "$v" != "disable" ]]; then
      row I deep-link-value finding warning "$surface" "disableDeepLinkRegistration:$v" "the key is present with $v; the one documented value that prevents registration is the string \"disable\"" /disableDeepLinkRegistration
    else
      row I deep-link-value ok none "$surface" "disableDeepLinkRegistration:disable" "set to \"disable\"" -
    fi
  fi
}
[[ $PROJECT_OK -eq 1 ]] && check_i "$SETTINGS" "$SURF_SETTINGS"
[[ $USER_OK -eq 1 ]] && check_i "$USER_SETTINGS" "$SURF_USER"

# --- Assemble ----------------------------------------------------------------------

rows_json="$(printf '%s\n' "${ROWS[@]}" | jq -cs '.')"
findings_json="$(if [[ ${#FINDINGS[@]} -gt 0 ]]; then printf '%s\n' "${FINDINGS[@]}" | jq -cs '.'; else echo '[]'; fi)"
suppressed_json="$(if [[ ${#SUPPRESSED[@]} -gt 0 ]]; then printf '%s\n' "${SUPPRESSED[@]}" | jq -cs '.'; else echo '[]'; fi)"
personal_json="$(if [[ ${#PERSONAL_ONLY[@]} -gt 0 ]]; then printf '%s\n' "${PERSONAL_ONLY[@]}" | jq -R . | jq -cs '.'; else echo '[]'; fi)"
malformed_json="$(if [[ ${#MALFORMED[@]} -gt 0 ]]; then printf '%s\n' "${MALFORMED[@]}" | jq -R . | jq -cs '.'; else echo '[]'; fi)"

DOC="$(jq -n \
  --arg root "$PROJECT_ROOT" \
  --argjson scopes "$SCOPES_JSON" \
  --argjson rows "$rows_json" \
  --argjson findings "$findings_json" \
  --argjson suppressed "$suppressed_json" \
  --argjson personal "$personal_json" \
  --argjson malformed "$malformed_json" \
  --argjson inv "$(jq -c '{inventory:.inventory, levers:(.levers // []), unreadable:(.unreadable // []), divergence:(.divergence // [])}' <<<"$INVENTORY_JSON")" \
  --argjson coverage "$COVERAGE_JSON" \
  --arg drift_state "$DRIFT_STATE" \
  --argjson listing "$G_JSON" \
  --argjson errors "$ERROR_COUNT" \
  '{engine:"claude-config/audit-engine/1",project_root:$root,scopes:$scopes,
    hook_inventory:$inv,coverage_manifests:$coverage,drift:{state:$drift_state},skill_listing:$listing,
    suppressions:{applied:$suppressed,personal_only:$personal,malformed:$malformed},
    summary:{rows:($rows|length),findings:($findings|length),errors:$errors,
      warnings:([$findings[]|select(.severity=="warning")]|length),
      info:([$findings[]|select(.severity=="info")]|length)},
    rows:$rows,findings:$findings}')"

if [[ -n "$OUT" ]]; then
  jq -n --argjson f "$findings_json" --argjson s "$suppressed_json" --arg root "$PROJECT_ROOT" \
    '{schemaVersion:1,producer:"claude-config/audit-engine/1",target:$root,lane:"claude-config/audit",findings:$f,suppressed:$s}' >"$OUT"
fi

if [[ "$MODE" == "json" ]]; then
  jq '.' <<<"$DOC"
else
  echo "Audit engine"
  echo "============"
  echo "Project root: $PROJECT_ROOT"
  jq -r '.scopes[] | "  \(.label): \(.state) (\(.path))"' <<<"$DOC"
  echo
  jq -r '.summary | "Rows: \(.rows)  Findings: \(.findings)  errors=\(.errors) warnings=\(.warnings) info=\(.info)"' <<<"$DOC"
  echo
  echo "Findings:"
  jq -r '.findings[] | "  [\(.severity)] \(.category) \(.identity.check | sub("^claude-config/audit/"; "")) \(.identity.claim)\n      \(.detail)\n      suppress: id \(.finding_id) surface \(.identity.sites[0].surface) anchor \(.identity.sites[0]["anchor/v1"])"' <<<"$DOC"
  echo
  echo "Suppressed:"
  jq -r '.suppressions.applied[]? | "  \(.check | sub("^claude-config/audit/"; "")) \(.claim): \(.suppressed.reason) (\(.suppressed.layer), \(.suppressed.date))"' <<<"$DOC"
  jq -r '.suppressions.personal_only[]? | "  \(.)"' <<<"$DOC"
  jq -r '.suppressions.malformed[]? | "  malformed: \(.)"' <<<"$DOC"
  echo
  echo "Skipped or not inspectable:"
  jq -r '.rows[] | select(.status=="skip" or .status=="not-inspectable") | "  \(.category) \(.check | sub("^claude-config/audit/"; "")): \(.detail)"' <<<"$DOC"
  echo
  jq -r '.skill_listing | if .measured then "Skill listing: measured from \(.log); overflow=\(.overflow)" else "Skill listing: not measured" end' <<<"$DOC"
  [[ -n "$OUT" ]] && echo "Findings written to: $OUT"
fi

[[ $ERROR_COUNT -eq 0 ]] && exit 0
exit 1
