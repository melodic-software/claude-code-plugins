#!/usr/bin/env bash
# Deterministic engine for the audit skill.
#
# WHAT IT DECIDES. Every audit row that a script can settle without a reading:
# schema, structure, and whether each settings key is documented or deprecated
# (A), the presence of each baseline permission pattern
# and the placement rules around it (B), MCP server shape (C), hook path, timeout
# shape, matcher class, placeholder quoting and duplicates (D), plugin membership
# and drift (E), the secret scan and env-vars documentation status (F), the
# skill-listing measurement from an existing debug log (G), model and effort
# values (H), and deep-link registration (I). Each decided row is emitted once,
# with the surface it is about and a stable identity, so the model that runs the
# audit reads one document instead of re-deriving the same facts with a dozen
# shell calls.
#
# WHERE ITS CRITERIA COME FROM. The upstream pages, read every run. The engine
# fetches the docs index (llms.txt) over the network with curl, resolves each
# page it needs (settings-reference, env-vars) from a link in that index, and
# reads it verbatim into a temp directory it removes on exit (trap). A page
# supplied through --docs-dir is read from there instead. Whether a key is
# documented or deprecated, the accepted effortLevel and
# disableDeepLinkRegistration values, and the version a key requires are taken
# from settings-reference; env-var documentation status from env-vars. A row
# resting on a page that was not read is not-inspectable, never clean. The
# engine also runs `claude --version` and records the result, and searches the
# installed claude binary for the literal names of undocumented keys. The
# document lists every page with its byte count and read state.
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
# already reports by value. It never runs a hook, and it writes nowhere except
# the path given to --out and its own temp directories.
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
#   SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR  directory holding llms.txt and <slug>.md; when set,
#                                       nothing is fetched and pages resolve through that llms.txt
#   SETTINGS_AUDIT_ENGINE_DOCS_INDEX_URL the docs index (default https://code.claude.com/docs/llms.txt)
#   SETTINGS_AUDIT_ENGINE_CLAUDE_BIN    the claude CLI to version and search (else `command -v claude`)
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
                a page found there is read instead of fetched
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

# The project-root, user-dir and registry ladders are shared vocabulary
# (lib/resolve-scopes.sh), not this script's to restate. Fail loudly rather than
# fall through: an unsourced library leaves every root empty and the audit would
# report a machine it never looked at.
RESOLVE_SCOPES_LIB="$PLUGIN_ROOT/lib/resolve-scopes.sh"
if [[ ! -r "$RESOLVE_SCOPES_LIB" ]]; then
  echo "ERROR: cannot read $RESOLVE_SCOPES_LIB; the plugin's shared scope-resolution library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/resolve-scopes.sh
source "$RESOLVE_SCOPES_LIB"

# Initialized here so ShellCheck SC2154 sees the assignment; the ladder fills it in.
PROJECT_ROOT=""
scopes::project_root_to PROJECT_ROOT "${SETTINGS_AUDIT_ENGINE_FIXTURE_DIR:-}"
PROJECT_ROOT="${PROJECT_ROOT//\\//}"
PROJECT_ROOT="${PROJECT_ROOT%/}"

USER_DIR=""
scopes::user_dir_to USER_DIR "${SETTINGS_AUDIT_ENGINE_USER_DIR:-}"

INSTALLED_JSON=""
scopes::installed_registry_to INSTALLED_JSON "${SETTINGS_AUDIT_ENGINE_INSTALLED_JSON:-}" "$USER_DIR"

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
  local layer="$1" file="$2" id check claim sites reason date rec_id
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

# --- Upstream sources: the docs pages and the installed CLI ---------------------
#
# Read here, after every early exit, so the identity subcommands and a fatal
# argument or settings error never reach the network or run the CLI.

DOCS_TMP="$(mktemp -d 2>/dev/null)"
if [[ -z "$DOCS_TMP" || ! -d "$DOCS_TMP" ]]; then
  echo "ERROR: could not create a temp directory for the docs pages" >&2
  exit 2
fi
trap 'rm -rf "$DOCS_TMP"' EXIT

DOCS_INDEX_URL="${SETTINGS_AUDIT_ENGINE_DOCS_INDEX_URL:-https://code.claude.com/docs/llms.txt}"
DOCS_ORIGIN=""
[[ "$DOCS_INDEX_URL" =~ ^([A-Za-z][A-Za-z0-9+.-]*://[^/]*) ]] && DOCS_ORIGIN="${BASH_REMATCH[1]}"
# Set, even to an empty or missing directory, means no network: a seam that
# points nowhere reads as unread pages, never as a fall back to the fetch.
DOCS_FIXTURE_SET=0
[[ -n "${SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR+x}" ]] && DOCS_FIXTURE_SET=1
DOCS_FIXTURE="${SETTINGS_AUDIT_ENGINE_DOCS_FIXTURE_DIR:-}"
# Every control character but tab and newline, CR included, is dropped from the
# working copy of a page, so text quoted from it into a row or the table never
# carries one. Byte counts are taken from the page as read.
DOC_CNTRL='\000-\010\013-\037\177'

# fetch_verbatim <url> <dest>: the whole body or nothing. A timeout or an HTTP
# error mid-download leaves no partial file to be counted as read (return 1).
# HTTPS only, redirects included, and a redirect that lands outside the docs
# origin is refused after the fact (return 2): the origin check on the linked
# URL says nothing about where a redirected body came from.
fetch_verbatim() {
  local effective
  if effective="$(curl -fsSL --proto =https --proto-redir =https --max-redirs 5 --connect-timeout 15 --max-time 120 \
    -w '%{url_effective}' -o "$2" "$1" 2>/dev/null)" && [[ -s "$2" ]]; then
    [[ -n "$DOCS_ORIGIN" && "$effective" == "$DOCS_ORIGIN/docs/"* ]] && return 0
    rm -f "$2"
    return 2
  fi
  rm -f "$2"
  return 1
}

# The index is read on the first page that needs it; a run whose pages all
# come from --docs-dir leaves it not-needed.
INDEX_STATE=""
INDEX_SOURCE=""
INDEX_BYTES=0
INDEX_REASON=""
load_index() {
  [[ -n "$INDEX_STATE" ]] && return 0
  local raw=""
  INDEX_STATE=unread
  if [[ $DOCS_FIXTURE_SET -eq 1 ]]; then
    INDEX_SOURCE=fixture
    if [[ -s "$DOCS_FIXTURE/llms.txt" ]]; then raw="$DOCS_FIXTURE/llms.txt"; else INDEX_REASON="fixture-missing"; fi
  elif ! command -v curl >/dev/null 2>&1; then
    INDEX_SOURCE=fetch
    INDEX_REASON="curl-missing"
  else
    INDEX_SOURCE=fetch
    fetch_verbatim "$DOCS_INDEX_URL" "$DOCS_TMP/llms.raw"
    case $? in
    0) raw="$DOCS_TMP/llms.raw" ;;
    2) INDEX_REASON="redirected-off-origin" ;;
    *) INDEX_REASON="fetch-failed" ;;
    esac
  fi
  [[ -n "$raw" ]] || return 0
  INDEX_BYTES="$(wc -c <"$raw" | tr -d ' ')"
  tr -d "$DOC_CNTRL" <"$raw" >"$DOCS_TMP/llms.txt"
  INDEX_STATE="read"
}

# index_link <slug>: the first link URL in the index that ends in /<slug>.md.
index_link() {
  awk -v suf="/$1.md" '{
    while (match($0, /\]\([^) \t]+\)/)) {
      u = substr($0, RSTART + 2, RLENGTH - 3)
      $0 = substr($0, RSTART + RLENGTH)
      if (length(u) >= length(suf) && substr(u, length(u) - length(suf) + 1) == suf) { print u; exit }
    }
  }' "$DOCS_TMP/llms.txt"
}

declare -A PAGE_FILE=()
DOCS_PAGES_JSON='[]'
# acquire_page <slug>: read the page verbatim into the temp directory (control
# characters stripped) and record where it came from, its byte count, and its state.
acquire_page() {
  local slug="$1" src="" loc="" raw="" reason="" state=unread bytes=0
  if [[ -n "$DOCS_DIR" && -s "$DOCS_DIR/$slug.md" ]]; then
    src=docs-dir
    loc="$DOCS_DIR/$slug.md"
    raw="$loc"
  else
    load_index
    if [[ "$INDEX_STATE" != "read" ]]; then
      reason="index-unread"
    else
      loc="$(index_link "$slug")"
      if [[ -z "$loc" ]]; then
        reason="not-in-index"
      elif [[ -z "$DOCS_ORIGIN" || "$loc" != "$DOCS_ORIGIN/docs/"* ]]; then
        reason="off-origin"
      elif [[ $DOCS_FIXTURE_SET -eq 1 ]]; then
        src=fixture
        if [[ -s "$DOCS_FIXTURE/$slug.md" ]]; then raw="$DOCS_FIXTURE/$slug.md"; else reason="fixture-missing"; fi
      else
        src=fetch
        fetch_verbatim "$loc" "$DOCS_TMP/$slug.raw"
        case $? in
        0) raw="$DOCS_TMP/$slug.raw" ;;
        2) reason="redirected-off-origin" ;;
        *) reason="fetch-failed" ;;
        esac
      fi
    fi
  fi
  if [[ -n "$raw" ]]; then
    bytes="$(wc -c <"$raw" | tr -d ' ')"
    tr -d "$DOC_CNTRL" <"$raw" >"$DOCS_TMP/$slug.md"
    PAGE_FILE[$slug]="$DOCS_TMP/$slug.md"
    state="read"
  fi
  DOCS_PAGES_JSON="$(jq -c --arg s "$slug" --arg l "$loc" --arg src "$src" --argjson b "$bytes" --arg st "$state" --arg r "$reason" \
    '. + [{slug:$s,url_or_path:$l,source:$src,bytes:$b,state:$st,reason:$r}]' <<<"$DOCS_PAGES_JSON")"
}
acquire_page settings-reference
acquire_page env-vars
[[ -n "$INDEX_STATE" ]] || INDEX_STATE=not-needed
SR="${PAGE_FILE[settings-reference]:-}"
EV="${PAGE_FILE[env-vars]:-}"

# The CLI. A seam that is set but names nothing is unreadable, never a fall
# back to the claude on PATH.
if [[ -n "${SETTINGS_AUDIT_ENGINE_CLAUDE_BIN+x}" ]]; then
  CLAUDE_BIN="$SETTINGS_AUDIT_ENGINE_CLAUDE_BIN"
else
  CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
  [[ -n "$CLAUDE_BIN" ]] && CLAUDE_BIN="$(readlink -f "$CLAUDE_BIN" 2>/dev/null || printf '%s' "$CLAUDE_BIN")" # portability-ok: a readlink without -f falls back to the unresolved path
fi
CLAUDE_RAW=""
CLAUDE_VERSION=""
if [[ -n "$CLAUDE_BIN" && -f "$CLAUDE_BIN" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    CLAUDE_RAW="$(timeout 30 "$CLAUDE_BIN" --version 2>/dev/null </dev/null | head -n 1)"
  else
    CLAUDE_RAW="$("$CLAUDE_BIN" --version 2>/dev/null </dev/null | head -n 1)"
  fi
  # Control characters (a terminal escape, a CR) never reach a row or the table.
  CLAUDE_RAW="$(tr -d '[:cntrl:]' <<<"$CLAUDE_RAW")"
  [[ "$CLAUDE_RAW" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]] && CLAUDE_VERSION="${BASH_REMATCH[1]}"
fi

# version_lt <a> <b>: true when x.y.z a is older than b, compared numerically.
version_lt() {
  local IFS=. i
  local -a a b
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  for i in 0 1 2; do
    ((10#${a[i]:-0} < 10#${b[i]:-0})) && return 0
    ((10#${a[i]:-0} > 10#${b[i]:-0})) && return 1
  done
  return 1
}

# settings-reference, parsed once: every ### `key` heading, the first line of
# its section that begins "Deprecated", and the first "Requires Claude Code
# vX.Y.Z". A section ends at the next heading of any level outside a code fence.
declare -A SR_KEY=()
declare -A SR_DEPRECATED=()
declare -A SR_REQUIRES=()
declare -A PERM_TYPE_KEYS=()
if [[ -n "$SR" ]]; then
  while IFS=$'\t' read -r k dep req; do
    [[ -n "$k" ]] || continue
    SR_KEY[$k]=1
    [[ "$dep" != "-" ]] && SR_DEPRECATED[$k]="$dep"
    [[ "$req" != "-" ]] && SR_REQUIRES[$k]="$req"
  done < <(awk '
    function flush() { if (key != "") printf "%s\t%s\t%s\n", key, (dep == "" ? "-" : dep), (req == "" ? "-" : req); key = "" }
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^(#|##|###|####) / {
      flush()
      if ($0 ~ /^### `[^`]+`$/) { key = $0; sub(/^### `/, "", key); sub(/`$/, "", key); dep = ""; req = "" }
      next
    }
    key == "" { next }
    dep == "" && /^[[:space:]]*Deprecated/ { dep = $0; sub(/^[[:space:]]+/, "", dep); gsub(/\t/, " ", dep) }
    req == "" && match($0, /Requires Claude Code v[0-9]+\.[0-9]+\.[0-9]+/) { req = substr($0, RSTART + 22, RLENGTH - 22) }
    END { flush() }
  ' "$SR")
fi

# sr_section <key>: the body of the key's section on settings-reference.
sr_section() {
  awk -v h="### \`$1\`" '
    /^[[:space:]]*```/ { fence = !fence; if (in_s) print; next }
    !fence && /^(#|##|###|####) / { if (in_s) exit; in_s = ($0 == h); next }
    in_s { print }
  ' "$SR"
}

# type_values <key>: the string values the key's Type bullet accepts, one per
# line, from either shape the page uses: "string, one of:" followed by nested
# `"value"` bullets, or "the string `"value"`". Nothing when neither parses.
type_values() {
  sr_section "$1" | awk '
    mode == "list" {
      if ($0 ~ /^[[:space:]]+\* `"[^"]*"`/) { v = $0; sub(/^[[:space:]]+\* `"/, "", v); sub(/"`.*$/, "", v); print v; next }
      exit
    }
    /^\* \*\*Type\*\*:/ {
      if ($0 ~ /string, one of:[[:space:]]*$/) { mode = "list"; next }
      if (match($0, /the string `"[^"]*"`/)) print substr($0, RSTART + 13, RLENGTH - 15)
      exit
    }
  '
}

# The permissions object's Type bullet names the nested keys it takes, which
# covers one with no heading of its own.
if [[ -n "$SR" ]]; then
  while IFS= read -r pk; do
    [[ -n "$pk" ]] && PERM_TYPE_KEYS[$pk]=1
  done < <(sr_section permissions | grep -m1 -E '^\* \*\*Type\*\*:' | grep -oE '`[^`]+`' | tr -d '`')
fi

# Positive control: a page that was read but has no heading for two keys every
# version documents (a soft 404, a reshaped page) did not parse, and every row
# resting on it is not-inspectable rather than a run of undocumented keys.
SR_UNREAD_WHY="settings-reference was not read this run"
if [[ -n "$SR" && ( -z "${SR_KEY[permissions]:-}" || -z "${SR_KEY[enabledPlugins]:-}" ) ]]; then
  SR=""
  SR_UNREAD_WHY="settings-reference was read but has no heading for permissions or enabledPlugins, so it did not parse"
  DOCS_PAGES_JSON="$(jq -c 'map(if .slug == "settings-reference" then .state = "unparsed" | .reason = "no-key-headings" else . end)' <<<"$DOCS_PAGES_JSON")"
fi

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

# Documented and deprecated keys: every top-level and permissions.* key is
# looked up on settings-reference. A key with no heading there is not reported
# as ignored, because the page omits keys the CLI manages itself; the installed
# binary settles it, searched once for every such key after the scopes are read.
KP_SURF=() KP_KEY=() KP_LEAF=() KP_PTR=()
check_keys() {
  # check_keys <file> <surface>
  local file="$1" surface="$2" k leaf ptr dep since
  # Fields arrive NUL-separated, so a key reaches its claim and the binary
  # search exactly as written in the file: no tab-separated escaping.
  while IFS= read -r -d '' k && IFS= read -r -d '' leaf && IFS= read -r -d '' ptr; do
    [[ -n "$k" ]] || continue
    if [[ -z "$SR" ]]; then
      row A key-documented not-inspectable none "$surface" "key-page-not-fetched:$k" "$SR_UNREAD_WHY; whether $k is documented is not decided" -
      continue
    fi
    if [[ -z "${SR_KEY[$k]:-}" ]] && ! [[ "$ptr" == /permissions/* && -n "${PERM_TYPE_KEYS[$leaf]:-}" ]]; then
      KP_SURF+=("$surface") KP_KEY+=("$k") KP_LEAF+=("$leaf") KP_PTR+=("$ptr")
      continue
    fi
    dep="${SR_DEPRECATED[$k]:-}"
    if [[ -z "$dep" ]]; then
      row A key-documented ok none "$surface" "documented-key:$k" "$k is documented on settings-reference" -
      continue
    fi
    if [[ "$dep" =~ since\ v([0-9]+\.[0-9]+\.[0-9]+) ]]; then
      since="${BASH_REMATCH[1]}"
      if [[ -z "$CLAUDE_VERSION" ]]; then
        row A key-deprecated skip none "$surface" "deprecated-key:$k" "settings-reference deprecates $k since v$since and the installed Claude Code version could not be read; not decided" -
        continue
      fi
      if version_lt "$CLAUDE_VERSION" "$since"; then
        row A key-deprecated ok none "$surface" "deprecated-key:$k" "installed v$CLAUDE_VERSION predates v$since, where settings-reference deprecates $k" -
        continue
      fi
    fi
    row A key-deprecated finding warning "$surface" "deprecated-key:$k" "settings-reference: \"$dep\"" "$ptr"
    # An empty key name has no literal to look up, so it is left out here.
  done < <(jqf "$file" -j 'if type == "object" then ((keys_unsorted[] | select(. != "$schema" and . != "") | [., ., "/" + .]), ((.permissions // {}) | if type == "object" then keys_unsorted[] | select(. != "") | ["permissions." + ., ., "/permissions/" + .] else empty end)) | (.[0], "\u0000", .[1], "\u0000", .[2], "\u0000") else empty end')
}
[[ $PROJECT_OK -eq 1 ]] && check_keys "$SETTINGS" "$SURF_SETTINGS"
[[ $LOCAL_OK -eq 1 ]] && check_keys "$LOCAL" "$SURF_LOCAL"
[[ $USER_OK -eq 1 ]] && check_keys "$USER_SETTINGS" "$SURF_USER"

# The binary is searched only for undocumented keys, once per literal, after
# two documented keys every build carries are found in it. A file missing
# either control (a .cmd shim, a wrapper script) was not really searched, so no
# key is called absent. Every undocumented key keeps one claim; only the
# severity and the detail say what the binary showed.
#
# The match is delimited: the name must stand alone, bounded on both sides by a
# character that cannot continue a JavaScript identifier, so `e` does not match
# inside `enabledPlugins`. Only an identifier-shaped name of four or more
# characters is searched; a shorter or odd-shaped one would match too much to
# prove anything and is reported as not searched. A hit shows the CLI carries
# the name as a standalone identifier or string, not that it reads the key.
BIN_SEARCH=not-needed
BIN_WORD='^[A-Za-z_][A-Za-z0-9_]{3,}$'
declare -A BIN_HAS=()
if [[ ${#KP_KEY[@]} -gt 0 ]]; then
  BIN_SEARCH=not-searched
  if [[ -n "$CLAUDE_BIN" && -f "$CLAUDE_BIN" && -r "$CLAUDE_BIN" ]] &&
    grep -aqF -- enabledPlugins "$CLAUDE_BIN" 2>/dev/null && grep -aqF -- permissions "$CLAUDE_BIN" 2>/dev/null; then
    BIN_SEARCH=searched
    for leaf in "${KP_LEAF[@]}"; do
      [[ -n "${BIN_HAS[$leaf]:-}" ]] && continue
      if [[ ! "$leaf" =~ $BIN_WORD ]]; then
        BIN_HAS[$leaf]=unsearchable
      elif grep -aqE -- "(^|[^A-Za-z0-9_\$])${leaf}([^A-Za-z0-9_\$]|\$)" "$CLAUDE_BIN" 2>/dev/null; then
        BIN_HAS[$leaf]=yes
      else
        BIN_HAS[$leaf]=no
      fi
    done
  fi
  for i in "${!KP_KEY[@]}"; do
    surface="${KP_SURF[$i]}" k="${KP_KEY[$i]}" leaf="${KP_LEAF[$i]}" ptr="${KP_PTR[$i]}"
    if [[ "$BIN_SEARCH" != "searched" ]]; then
      row A key-documented finding info "$surface" "undocumented-key:$k" "$k is not documented on settings-reference; the installed claude binary was not searched, so whether the CLI reads it is not known" "$ptr"
    elif [[ "${BIN_HAS[$leaf]}" == "unsearchable" ]]; then
      row A key-documented finding info "$surface" "undocumented-key:$k" "$k is not documented on settings-reference; its name is too short or not identifier-shaped for a binary search to settle, so whether the CLI reads it is not known" "$ptr"
    elif [[ "${BIN_HAS[$leaf]}" == "yes" ]]; then
      row A key-documented finding info "$surface" "undocumented-key:$k" "$k is not documented on settings-reference; the installed claude binary carries $leaf as a standalone name, so it may be an internal key the CLI manages (this shows the name is in the CLI, not that the CLI reads it)" "$ptr"
    else
      row A key-documented finding warning "$surface" "undocumented-key:$k" "$k is in neither settings-reference nor the installed claude binary; Claude Code may ignore it" "$ptr"
    fi
  done
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
  if [[ ${#BASELINE_ORDER[@]} -eq 0 ]]; then
    # Present but yielding nothing is a parse failure, not an empty baseline:
    # a renamed family heading or a reshaped table would otherwise make every
    # category B row vanish and the report read as clean.
    row B baseline-reference skip none "$SURF_SETTINGS" "reference-unparsed" "required-permissions.md at $BASELINE_FILE yielded no Tool(...) pattern under its family headings; baseline presence not decided" -
  fi
else
  row B baseline-reference skip none "$SURF_SETTINGS" "reference-missing" "required-permissions.md not found at $BASELINE_FILE; baseline presence not decided" -
fi

# --- Hook inventory (delegated to check-hook-coverage.sh) ---------------------

INVENTORY_JSON='{"inventory":"none","hooks":[],"plugins":[],"levers":[],"unreadable":[],"divergence":[]}'
if [[ -x "$SCRIPT_DIR/check-hook-coverage.sh" || -f "$SCRIPT_DIR/check-hook-coverage.sh" ]]; then
  inv_out="$(HOOK_COVERAGE_FIXTURE_DIR="$PROJECT_ROOT" HOOK_COVERAGE_USER_DIR="$USER_DIR" \
    HOOK_COVERAGE_INSTALLED_JSON="$INSTALLED_JSON" HOOK_COVERAGE_MANAGED_JSON="${SETTINGS_AUDIT_MANAGED_PATH:-}" \
    bash "$SCRIPT_DIR/check-hook-coverage.sh" --json 2>/dev/null)"
  inventory_exit=$?
  if [[ $inventory_exit -ne 2 ]] && jq empty <<<"$inv_out" 2>/dev/null; then
    INVENTORY_JSON="$(tr -d '\r' <<<"$inv_out")"
  fi
fi
INVENTORY_STATE="$(jqs -r '.inventory // "none"' <<<"$INVENTORY_JSON")"

# Lever reading: a hook one of these has switched off is not coverage. An
# unread lever is not an unset lever: when a settings scope did not parse, the
# inventory reports the lever state unknown and the narrowing is unavailable,
# because a lever that disables every hook may be sitting in the file nothing
# could read.
LEVER_DISABLE_ALL="$(jqs -r '[.levers[]? | select(.key=="disableAllHooks" and .value=="true")] | length' <<<"$INVENTORY_JSON")"
LEVER_MANAGED="$(jqs -r '[.levers[]? | select((.key=="allowManagedHooksOnly" or .key=="strictPluginOnlyCustomization") and .value=="true")] | length' <<<"$INVENTORY_JSON")"
LEVER_STATE="$(jqs -r '.lever_state // "complete"' <<<"$INVENTORY_JSON")"
HOOKS_LIVE=1
HOOKS_LIVE_REASON="a suppression lever is set, so the hook is not live"
if [[ "$LEVER_STATE" != "complete" ]]; then
  HOOKS_LIVE=0
  HOOKS_LIVE_REASON="a settings scope did not parse, so the suppression levers could not be read and the hook cannot be assumed live"
  row D lever-state not-inspectable none "settings" "lever-state-unknown" "a settings scope did not parse, so disableAllHooks and the managed levers were not read; hook coverage cannot narrow any baseline family" -
elif [[ "${LEVER_DISABLE_ALL:-0}" != "0" || "${LEVER_MANAGED:-0}" != "0" ]]; then
  HOOKS_LIVE=0
fi

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
    # A manifest entry narrows only when the hook it names is one this plugin
    # actually registers on that event and matcher. An entry naming a hook
    # that is not there would otherwise demote a missing deny on the strength
    # of enforcement code that does not exist.
    m_hook="$(jqs -r '.hook' <<<"$entry")"
    m_matcher="$(jqs -r '.matcher' <<<"$entry")"
    # The command is matched on the hook's file name, not its manifest path: a
    # plugin may register one dispatcher that runs the named guard as an
    # argument, and that dispatcher is the enforcement the manifest claims.
    m_base="${m_hook##*/}"
    live_match=0
    [[ -n "$m_base" ]] && live_match="$(jqs -r --arg s "plugin:$pkey" --arg m "$m_matcher" --arg h "$m_base" \
      '[.hooks[]? | select(.source==$s and .event=="PreToolUse" and .matcher==$m and (.command | contains($h)))] | length' <<<"$INVENTORY_JSON")"
    if [[ "${live_match:-0}" == "0" ]]; then
      row D coverage-manifest finding warning "plugin:$pkey" "manifest-hook-not-inventoried:$m_hook:$m_matcher" "coverage.json names $m_hook on PreToolUse/$m_matcher, but no enumerated hook of this plugin matches; no narrowing taken from this entry" hooks/coverage.json
      continue
    fi
    levers="$(jqs -r '[.levers[]? | .name] | join(", ")' <<<"$entry")"
    while IFS= read -r pat; do
      [[ -n "$pat" ]] || continue
      # The tool surface the pattern defends must be on the matcher: a Read
      # pattern is never covered by a Bash hook.
      tool="${pat%%(*}"
      case "|$m_matcher|" in
      *"|$tool|"*) ;;
      *"*"*) ;;
      *) continue ;;
      esac
      COVERED_BY[$pat]="$pkey $m_hook (levers: ${levers:-none})"
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
        row B "baseline-$fam" finding "$sev" "$SURF_SETTINGS" "missing-pattern:$pat" "not in permissions.$target; a hook declares coverage (${COVERED_BY[$pat]}) but $HOOKS_LIVE_REASON" "/permissions/$target"
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
    sorted_servers="$(printf '%s\n' "$servers" | sort)"
    listed_servers="$(jqf "$SETTINGS" -r '((.enabledMcpjsonServers // []) + (.disabledMcpjsonServers // []))[]' | sort)"
    uncovered="$(comm -23 <(printf '%s\n' "$sorted_servers") <(printf '%s\n' "$listed_servers") | grep -v '^$' || true)"
    while IFS= read -r u; do
      [[ -n "$u" ]] || continue
      row C server-coverage finding error "$SURF_SETTINGS" "unlisted-server:$u" "$u is in .mcp.json but in neither enabledMcpjsonServers nor disabledMcpjsonServers" /enabledMcpjsonServers
    done <<<"$uncovered"
    unknown="$(comm -13 <(printf '%s\n' "$sorted_servers") <(printf '%s\n' "$listed_servers") | grep -v '^$' || true)"
    while IFS= read -r u; do
      [[ -n "$u" ]] || continue
      row C server-names finding error "$SURF_SETTINGS" "unknown-server:$u" "$u is listed in settings.json but is not a server in .mcp.json" /disabledMcpjsonServers
    done <<<"$unknown"
  fi
fi

# --- Category D: hooks ---------------------------------------------------------

# Token shapes that never belong in a claim or detail. Used here to redact a
# hook command and in category F to flag a tracked settings value.
SECRET_RE='ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{5,}|sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|xox[abp]-[A-Za-z0-9-]{10,}'

resolve_hook_path() {
  # resolve_hook_path <command> <plugin-path> -> the first token with placeholders expanded
  local cmd="$1" ppath="$2" first="" c i inq=0
  # The first shell word, read the way the shell would: whitespace ends it
  # only outside quotes, so "$CLAUDE_PROJECT_DIR/my hooks/x.sh" and the
  # common "${CLAUDE_PLUGIN_ROOT}"/hooks/x.sh both stay whole, and the quote
  # characters themselves are dropped as the shell drops them.
  for ((i = 0; i < ${#cmd}; i++)); do
    c="${cmd:i:1}"
    if [[ "$c" == '"' || "$c" == "'" ]]; then
      inq=$((1 - inq))
      continue
    fi
    if [[ $inq -eq 0 && "$c" == [[:space:]] ]]; then
      [[ -n "$first" ]] && break
      continue
    fi
    first+="$c"
  done
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
  [[ "$timeout" == "-" ]] && timeout=""
  [[ "$hif" == "-" ]] && hif=""
  surface="$src"
  [[ "$src" == "settings:project" ]] && surface="$SURF_SETTINGS"
  [[ "$src" == "settings:local" ]] && surface="$SURF_LOCAL"
  [[ "$src" == "settings:user" ]] && surface="$SURF_USER"
  # A command from a personal scope, or one carrying a token-shaped value in
  # any scope, is named by its excerpt hash in every claim and detail: the
  # claim is what an operator pastes into the tracked suppression record. The
  # raw command still feeds the anchor, which stores only a hash.
  cmd_ref="$cmd"
  cmd_public=1
  if [[ "$surface" == "$SURF_LOCAL" || "$surface" == "$SURF_USER" ]] || printf '%s' "$cmd" | grep -Eq "$SECRET_RE"; then
    cmd_ref="cmd:$(anchor_for_excerpt "$cmd")"
    cmd_public=0
  fi
  key="$src|$event|$matcher|$cmd|$hif"
  if [[ -n "${HOOK_SEEN[$key]:-}" ]]; then
    row D duplicate-hook finding info "$surface" "duplicate-hook:$event:$matcher:$cmd_ref" "the same command is registered twice for $event/$matcher" "$event/$matcher/$cmd"
  fi
  HOOK_SEEN[$key]=1
  [[ "$htype" == "command" || -z "$htype" ]] || continue
  # Timeout shape: a round thousands multiple reads as milliseconds.
  if [[ -n "$timeout" && "$timeout" =~ ^[0-9]+$ && $timeout -ge 1000 && $((timeout % 1000)) -eq 0 ]]; then
    row D timeout-unit finding warning "$surface" "millisecond-timeout:$event:$cmd_ref" "timeout $timeout reads as milliseconds; the field is seconds" "$event/$matcher/$cmd"
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
      row D placeholder-quoting finding warning "$surface" "unquoted-placeholder:$event:$cmd_ref" "a path placeholder in shell form is not wrapped in double quotes; a space in the path breaks the hook" "$event/$matcher/$cmd"
    fi
  fi
  # Path resolution for the first token when it is a path.
  ppath="${PLUGIN_PATH[$src]:-}"
  first="$(resolve_hook_path "$cmd" "$ppath")"
  first_shown="$first"
  [[ $cmd_public -eq 1 ]] || first_shown="the resolved first token"
  case "$first" in
  */*)
    if [[ "$first" == *'$'* ]]; then
      row D hook-path skip none "$surface" "unexpanded-placeholder:$cmd_ref" "first token still carries a placeholder this engine cannot expand; the model resolves it" -
    elif [[ ! -e "$first" ]]; then
      row D hook-path finding error "$surface" "hook-path-missing:$event:$cmd_ref" "$first_shown does not exist" "$event/$matcher/$cmd"
    elif [[ ! -r "$first" ]]; then
      row D hook-path finding error "$surface" "hook-path-unreadable:$event:$cmd_ref" "$first_shown is not readable" "$event/$matcher/$cmd"
    else
      row D hook-path ok none "$surface" "hook-path-resolves:$event:$cmd_ref" "$first_shown exists and is readable" -
    fi
    ;;
  *) ;;
  esac
  # Empty middle fields carry a "-" sentinel: `read` with a tab IFS folds
  # consecutive tabs, so a hook with no timeout would otherwise shift its type
  # into the timeout column and drop out of every check above.
done < <(jqs -r '.hooks[]? | [.source, .event, .matcher, .command, ((.timeout // "-") | tostring), (.type // "command"), ((.if // "-") | if . == "" then "-" else . end), ((.args // []) | tojson)] | @tsv' <<<"$INVENTORY_JSON")

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
    if ! grep -qxF -- "$market" <<<"$known_markets"; then
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
# The drift script runs whether or not curl is present: a directory-sourced
# marketplace is read from disk, and a repo-sourced one it cannot fetch comes
# back as a skipped marketplace with its reason, reported below.
if [[ "${SETTINGS_AUDIT_ENGINE_SKIP_DRIFT:-0}" != "1" && $PROJECT_OK -eq 1 && -f "$SCRIPT_DIR/check-plugin-drift.sh" ]]; then
  drift_tmp="$(mktemp)"
  NO_COLOR=1 CLAUDE_SETTINGS_FILE="$SETTINGS" SETTINGS_AUDIT_OUTPUT_JSON="$drift_tmp" \
    bash "$SCRIPT_DIR/check-plugin-drift.sh" >/dev/null 2>&1
  if [[ -s "$drift_tmp" ]] && jq empty "$drift_tmp" 2>/dev/null; then
    DRIFT_JSON="$(tr -d '\r' <"$drift_tmp")"
    DRIFT_STATE=ran
  fi
  rm -f "$drift_tmp"
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
    grep -qxF -- "$name@$mk" <<<"$merged_keys" && continue
    row E drift-new finding info "$SURF_SETTINGS" "new-upstream:$name@$mk" "$name@$mk is in the $mk catalog and has no enabledPlugins entry in any scope; record an explicit true or false" "/enabledPlugins/$name@$mk"
  done < <(jqs -r '.[] | .new_upstream[]? | [.name, .marketplace] | @tsv' <<<"$DRIFT_JSON")
  while IFS=$'\t' read -r from to mk; do
    [[ -n "$from" ]] || continue
    row E drift-rename finding warning "$SURF_SETTINGS" "possible-rename:$from->$to@$mk" "$from may have been renamed to $to in $mk; confirm before editing the key" "/enabledPlugins/$from@$mk"
  done < <(jqs -r '.[] | .renames[]? | [.from, .to, .marketplace] | @tsv' <<<"$DRIFT_JSON")
else
  row E drift skip none "$SURF_SETTINGS" "drift-not-run" "plugin drift not computed (skipped, no project settings, or the drift script produced no document)" -
fi

# --- Category F: environment variables -----------------------------------------

if [[ $PROJECT_OK -eq 1 ]]; then
  if tr -d '\r' <"$SETTINGS" | grep -Eq "$SECRET_RE"; then
    row F secrets finding error "$SURF_SETTINGS" "secret-shaped-value" "a token-shaped value is present in the tracked settings file; move it to settings.local.json or a credential store" /env
  else
    row F secrets ok none "$SURF_SETTINGS" "no-secret-shaped-value" "no token-shaped value in settings.json" -
  fi
  while IFS= read -r ek; do
    [[ -n "$ek" ]] || continue
    if [[ -n "$EV" ]]; then
      if grep -qF -- "\`$ek\`" "$EV"; then
        row F documented-var ok none "$SURF_SETTINGS" "documented-on-env-vars:$ek" "$ek is documented on env-vars" -
      else
        row F documented-var finding info "$SURF_SETTINGS" "not-on-env-vars-page:$ek" "$ek is not on the env-vars page; it may be documented elsewhere or be a justified custom variable (the model decides)" "/env/$ek"
      fi
    else
      row F documented-var not-inspectable none "$SURF_SETTINGS" "env-page-not-fetched:$ek" "env-vars was not read this run; documentation status of $ek not decided" -
    fi
  done < <(jqf "$SETTINGS" -r '(.env // {}) | keys_unsorted[] | [.] | @tsv')
fi

# --- Category G: skill-listing measurement from an existing debug log ----------

DEBUG_LOG=""
# explicit: named by the operator or the session (a file path, per env-vars).
# discovered: the newest log in the debug directory, which may belong to an
# earlier session or another project; it decides only when it names this
# project root, and otherwise a clean read is reported as unverified.
DEBUG_LOG_PROVENANCE="explicit"
if [[ -n "$DEBUG_LOG_ARG" && -f "$DEBUG_LOG_ARG" ]]; then
  DEBUG_LOG="$DEBUG_LOG_ARG"
elif [[ -n "${CLAUDE_CODE_DEBUG_LOGS_DIR:-}" && -f "${CLAUDE_CODE_DEBUG_LOGS_DIR}" ]]; then
  DEBUG_LOG="$CLAUDE_CODE_DEBUG_LOGS_DIR"
else
  DEBUG_LOG_PROVENANCE="discovered"
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
  if [[ "$DEBUG_LOG_PROVENANCE" == "discovered" ]] && grep -qF -- "$PROJECT_ROOT" "$DEBUG_LOG" 2>/dev/null; then
    DEBUG_LOG_PROVENANCE="project"
  fi
  gline="$(grep -E 'Skill listing over budget: [0-9]+ skills, [0-9]+ chars > [0-9]+ budget' "$DEBUG_LOG" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$gline" ]]; then
    g_skills="$(sed -E 's/.*over budget: ([0-9]+) skills.*/\1/' <<<"$gline")"
    g_chars="$(sed -E 's/.*skills, ([0-9]+) chars.*/\1/' <<<"$gline")"
    g_budget="$(sed -E 's/.*chars > ([0-9]+) budget.*/\1/' <<<"$gline")"
    G_JSON="$(jq -cn --arg log "$DEBUG_LOG" --arg p "$DEBUG_LOG_PROVENANCE" --argjson s "$g_skills" --argjson c "$g_chars" --argjson b "$g_budget" \
      '{measured:true,route:"debug-log",provenance:$p,log:$log,skills:$s,chars:$c,budget:$b,over_by:($c-$b),overflow:true}')"
    row G listing-budget finding warning "settings" "listing-over-budget" "debug log $DEBUG_LOG ($DEBUG_LOG_PROVENANCE): $g_skills skills, $g_chars chars against a $g_budget budget, over by $((g_chars - g_budget)); descriptions of the least-used skills are cut" "skill-listing"
  elif [[ "$DEBUG_LOG_PROVENANCE" == "discovered" ]]; then
    G_JSON="$(jq -cn --arg log "$DEBUG_LOG" '{measured:false,route:"debug-log",provenance:"discovered",log:$log}')"
    row G listing-budget skip none "settings" "listing-unverified" "newest debug log $DEBUG_LOG carries no over-budget warning but does not name this project root, so it may be another session's; pass --debug-log with a log from a session in this project to decide" -
  else
    G_JSON="$(jq -cn --arg log "$DEBUG_LOG" --arg p "$DEBUG_LOG_PROVENANCE" '{measured:true,route:"debug-log",provenance:$p,log:$log,overflow:false}')"
    row G listing-budget ok none "settings" "listing-fits" "debug log $DEBUG_LOG ($DEBUG_LOG_PROVENANCE) carries no over-budget warning; the listing fit its budget in that session" -
  fi
else
  row G listing-budget skip none "settings" "listing-not-measured" "no debug log found (--debug-log, CLAUDE_CODE_DEBUG_LOGS_DIR, or <user dir>/debug/*.txt); measure with /doctor interactively or a --debug relaunch, never report clean" -
fi

# --- Category H: model and effort values -----------------------------------------

# documented_value <cat> <slug> <key> <value> <surface>: the value against the
# set the key's Type bullet on settings-reference accepts. The claim is
# <key>:<value> whatever the outcome, so a finding keeps one identity.
documented_value() {
  local cat="$1" slug="$2" key="$3" v="$4" surface="$5" accepted
  if [[ -z "$SR" ]]; then
    row "$cat" "$slug" not-inspectable none "$surface" "$key:$v" "$SR_UNREAD_WHY; the values $key accepts are not known" -
    return 0
  fi
  accepted="$(type_values "$key")"
  if [[ -z "$accepted" ]]; then
    row "$cat" "$slug" skip none "$surface" "$key:$v" "the Type bullet of $key on settings-reference did not parse to a value set; not decided" -
  elif [[ -n "$v" && "$v" != *$'\n'* && $'\n'"$accepted"$'\n' == *$'\n'"$v"$'\n'* ]]; then
    # A whole-string match: grep would read a multi-line value as several
    # patterns and pass "bogus<newline>high" on its second line.
    row "$cat" "$slug" ok none "$surface" "$key:$v" "$v is a value settings-reference documents for $key" -
  else
    row "$cat" "$slug" finding warning "$surface" "$key:$v" "$key is $v, which is not among the values its settings-reference Type bullet documents (${accepted//$'\n'/, })" "/$key"
  fi
}

check_h() {
  # check_h <file> <surface>
  local file="$1" surface="$2"
  local raw dedup mix enforce avail_len req
  if [[ "$(jqf "$file" -r 'has("effortLevel")')" == "true" ]]; then
    documented_value H effort-level effortLevel "$(jqf "$file" -r '.effortLevel | tostring')" "$surface"
  fi
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
    # Gated on the first "Requires Claude Code vX.Y.Z" in the key's section: on
    # an older CLI the key is not read at all, so the missing list costs nothing.
    req="${SR_REQUIRES[enforceAvailableModels]:-}"
    if [[ -z "$SR" ]]; then
      row H enforce-available not-inspectable none "$surface" "enforceAvailableModels-without-list" "$SR_UNREAD_WHY; the version enforceAvailableModels requires is not known" -
    elif [[ -n "$req" && -z "$CLAUDE_VERSION" ]]; then
      row H enforce-available skip none "$surface" "enforceAvailableModels-without-list" "enforceAvailableModels requires Claude Code v$req and the installed version could not be read; not decided" -
    elif [[ -n "$req" ]] && version_lt "$CLAUDE_VERSION" "$req"; then
      row H enforce-available ok none "$surface" "enforceAvailableModels-without-list" "installed v$CLAUDE_VERSION predates v$req, the first version that reads enforceAvailableModels" -
    else
      row H enforce-available finding error "$surface" "enforceAvailableModels-without-list" "enforceAvailableModels is true with no availableModels; the flag has no effect, so the Default option is not constrained" /enforceAvailableModels
    fi
  fi
}
[[ $PROJECT_OK -eq 1 ]] && check_h "$SETTINGS" "$SURF_SETTINGS"
[[ $LOCAL_OK -eq 1 ]] && check_h "$LOCAL" "$SURF_LOCAL"
[[ $USER_OK -eq 1 ]] && check_h "$USER_SETTINGS" "$SURF_USER"

# --- Category I: deep-link registration ------------------------------------------

check_i() {
  local file="$1" surface="$2"
  if [[ "$(jqf "$file" -r 'has("disableDeepLinkRegistration")')" == "true" ]]; then
    documented_value I deep-link-value disableDeepLinkRegistration "$(jqf "$file" -r '.disableDeepLinkRegistration | tostring')" "$surface"
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

inv_json="$(jq -c '{inventory:.inventory, levers:(.levers // []), unreadable:(.unreadable // []), divergence:(.divergence // [])}' <<<"$INVENTORY_JSON")"
version_json="$(jq -cn --arg raw "$CLAUDE_RAW" --arg v "$CLAUDE_VERSION" --arg bin "$CLAUDE_BIN" --arg search "$BIN_SEARCH" \
  '{raw:$raw,version:(if $v == "" then null else $v end),state:(if $v == "" then "unreadable" else "read" end),binary:{path:$bin,key_search:$search}}')"
docs_json="$(jq -c --arg url "$DOCS_INDEX_URL" --arg src "$INDEX_SOURCE" --argjson b "$INDEX_BYTES" --arg st "$INDEX_STATE" --arg r "$INDEX_REASON" \
  '{index:{url:$url,source:$src,bytes:$b,state:$st,reason:$r},pages:.}' <<<"$DOCS_PAGES_JSON")"

# The payloads ride stdin and are slurped, rather than being bound as --argjson
# values. The whole argv is ONE Win32 command line, and a single argument past
# about 32,760 bytes dies with "Argument list too long", which left $DOC empty
# and every reader below printing nothing while the exit code still said 1. A
# pipe has no such cap, and unlike --slurpfile it leaves no temp file to clean
# up. The `:-null` defaults keep the positional contract total: an empty payload
# would otherwise shift every later binding by one. `jq -s` slurps by JSON value,
# not by line, so a pretty-printed payload is still exactly one element. Only
# the three small scalars stay on argv; none can approach the cap.
DOC="$(printf '%s\n' \
  "${SCOPES_JSON:-null}" "${rows_json:-null}" "${findings_json:-null}" \
  "${suppressed_json:-null}" "${personal_json:-null}" "${malformed_json:-null}" \
  "${inv_json:-null}" "${COVERAGE_JSON:-null}" "${G_JSON:-null}" \
  "${version_json:-null}" "${docs_json:-null}" |
  jq -s \
    --arg root "$PROJECT_ROOT" \
    --arg drift_state "$DRIFT_STATE" \
    --argjson errors "$ERROR_COUNT" \
    '. as [$scopes,$rows,$findings,$suppressed,$personal,$malformed,$inv,$coverage,$listing,$version,$docs] |
     {engine:"claude-config/audit-engine/1",project_root:$root,claude_version:$version,docs:$docs,scopes:$scopes,
      hook_inventory:$inv,coverage_manifests:$coverage,drift:{state:$drift_state},skill_listing:$listing,
      suppressions:{applied:$suppressed,personal_only:$personal,malformed:$malformed},
      summary:{rows:($rows|length),findings:($findings|length),errors:$errors,
        warnings:([$findings[]|select(.severity=="warning")]|length),
        info:([$findings[]|select(.severity=="info")]|length)},
      rows:$rows,findings:$findings}')"

if [[ -n "$OUT" ]]; then
  # Same argv exposure, same transport change, and deliberately INDEPENDENT of
  # $DOC: this writer succeeds even when the assembly above does not, and reading
  # an empty $DOC would truncate the findings file to zero bytes, which is worse
  # for the audit-pass consumer than either outcome available today. No -c: the
  # findings file is a diffable artifact and stays pretty-printed.
  printf '%s\n' "${findings_json:-null}" "${suppressed_json:-null}" |
    jq -s --arg root "$PROJECT_ROOT" \
      '. as [$f,$s] | {schemaVersion:1,producer:"claude-config/audit-engine/1",target:$root,lane:"claude-config/audit",findings:$f,suppressed:$s}' >"$OUT"
fi

if [[ "$MODE" == "json" ]]; then
  jq '.' <<<"$DOC"
else
  echo "Audit engine"
  echo "============"
  echo "Project root: $PROJECT_ROOT"
  jq -r '.scopes[] | "  \(.label): \(.state) (\(.path))"' <<<"$DOC"
  jq -r '.claude_version | "Claude Code: \(.version // "unreadable") (\(.state); --version printed \"\(.raw)\")"' <<<"$DOC"
  echo "Docs read this run:"
  jq -r '.docs.index | "  index: \(.state) \(.bytes) bytes (\(.url))\(if .reason != "" then "; " + .reason else "" end)"' <<<"$DOC"
  jq -r '.docs.pages[] | "  \(.slug): \(.state) \(.bytes) bytes (\(.source) \(.url_or_path))\(if .reason != "" then "; " + .reason else "" end)"' <<<"$DOC"
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
