#!/usr/bin/env bash
# Apply plugin drift fixes to .claude/settings.json based on
# check-plugin-drift.sh findings.
#
# Auto-fix policy (settings-audit Category E):
#
#   ORPHAN, enabled=false  →  AUTO-REMOVE from enabledPlugins
#                              (behaviorally a no-op: false ≡ absent for plugin
#                              loading, and the entry references a nonexistent
#                              upstream plugin generating /doctor errors)
#
#   ORPHAN, enabled=true   →  REPORT ONLY (manual review required)
#                              (user explicitly enabled a plugin that is now
#                              gone upstream; auto-removing silently breaks
#                              their intent. Surface and let them decide)
#
#   NEW upstream            →  AUTO-ADD as enabledPlugins["<name>@<market>"] = false
#                              (records the discovery as an explicit opt-out,
#                              which keeps per-developer settings.local.json
#                              overrides functional)
#
#   RENAME                  →  REPORT ONLY (heuristic match, human reviews)
#
# Modes:
#   --dry-run  (default)   print plan, no writes
#   --yes      / -y        apply changes
#   --input <path>         consume existing JSON from check-plugin-drift.sh
#                          (otherwise re-runs the check internally)
#   --help                 print usage
#
# Env overrides:
#   CLAUDE_SETTINGS_FILE    path to project settings.json
#   SETTINGS_AUDIT_FIXTURE_DIR forwarded to check-plugin-drift.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Args --------------------------------------------------------------------

MODE="dry-run"
INPUT_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes | -y)
      MODE="apply"
      shift
      ;;
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --input)
      INPUT_JSON="$2"
      shift 2
      ;;
    --help | -h)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

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
  echo "ERROR: jq required" >&2
  exit 2
fi

# --- Output helpers ----------------------------------------------------------

if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
  RED="" YELLOW="" GREEN="" CYAN="" RESET=""
else
  RED=$'\033[31m' YELLOW=$'\033[33m' GREEN=$'\033[32m' CYAN=$'\033[36m' RESET=$'\033[0m'
fi

# --- Obtain findings ---------------------------------------------------------

TMP_JSON=""
if [[ -z "$INPUT_JSON" ]]; then
  TMP_JSON=$(mktemp -t plugin-drift-XXXXXX.json)
  trap 'rm -f "$TMP_JSON"' EXIT
  printf '%sRunning check-plugin-drift.sh...%s\n' "$CYAN" "$RESET" >&2
  SETTINGS_AUDIT_OUTPUT_JSON="$TMP_JSON" CLAUDE_SETTINGS_FILE="$SETTINGS" \
    bash "$SCRIPT_DIR/check-plugin-drift.sh" >/dev/null || true
  INPUT_JSON="$TMP_JSON"
fi

if [[ ! -f "$INPUT_JSON" ]]; then
  echo "ERROR: findings JSON not found: $INPUT_JSON" >&2
  exit 2
fi

if ! jq empty "$INPUT_JSON" 2>/dev/null; then
  echo "ERROR: findings JSON is not valid: $INPUT_JSON" >&2
  exit 2
fi

# --- Build action plan -------------------------------------------------------

# Auto-removable orphans: orphans where enabled == false. Output as
# "<plugin>@<marketplace>" lines.
auto_remove=$(jq -r '
  .[] | select(.status == "ok") | .orphans[] | select(.enabled == false) |
  "\(.name)@\(.marketplace)"
' "$INPUT_JSON" | sort -u)

# Manual-review orphans: orphans where enabled == true.
manual_orphans=$(jq -r '
  .[] | select(.status == "ok") | .orphans[] | select(.enabled == true) |
  "\(.name)@\(.marketplace)"
' "$INPUT_JSON" | sort -u)

# Auto-add: new upstream plugins.
auto_add=$(jq -r '
  .[] | select(.status == "ok") | .new_upstream[] |
  "\(.name)@\(.marketplace)"
' "$INPUT_JSON" | sort -u)

# Rename candidates (informational).
rename_candidates=$(jq -r '
  .[] | select(.status == "ok") | .renames[] |
  "\(.from) -> \(.to)  (\(.marketplace))"
' "$INPUT_JSON" | sort -u)

remove_count=$(echo "$auto_remove" | grep -c . || true)
add_count=$(echo "$auto_add" | grep -c . || true)
manual_count=$(echo "$manual_orphans" | grep -c . || true)
rename_count=$(echo "$rename_candidates" | grep -c . || true)

# --- Render plan -------------------------------------------------------------

printf '\n%sPlugin drift fix plan%s (mode: %s)\n' "$CYAN" "$RESET" "$MODE"
printf 'Settings file: %s\n\n' "$SETTINGS"

if [[ "$remove_count" -gt 0 ]]; then
  printf '%sAUTO-REMOVE%s %d orphan entries (enabled=false):\n' "$YELLOW" "$RESET" "$remove_count"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    printf '  - %s\n' "$entry"
  done <<<"$auto_remove"
  echo
fi

if [[ "$add_count" -gt 0 ]]; then
  # shellcheck disable=SC2016  # backticks are intentional markdown literal in user-facing output
  printf '%sAUTO-ADD%s %d new upstream plugins as `false`:\n' "$CYAN" "$RESET" "$add_count"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    printf '  - %s\n' "$entry"
  done <<<"$auto_add"
  echo
fi

if [[ "$manual_count" -gt 0 ]]; then
  printf '%sMANUAL REVIEW%s %d orphans currently enabled (true):\n' "$RED" "$RESET" "$manual_count"
  printf '  These plugins were intentionally enabled but are now gone upstream.\n'
  printf '  Auto-fix would silently break user intent — surfacing only:\n'
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    printf '    - %s\n' "$entry"
  done <<<"$manual_orphans"
  echo
fi

if [[ "$rename_count" -gt 0 ]]; then
  printf '%sRENAME?%s %d possible rename pairs (heuristic — review manually):\n' "$YELLOW" "$RESET" "$rename_count"
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    printf '  - %s\n' "$entry"
  done <<<"$rename_candidates"
  echo
fi

if [[ "$remove_count" -eq 0 && "$add_count" -eq 0 && "$manual_count" -eq 0 && "$rename_count" -eq 0 ]]; then
  printf '%sNo drift detected — nothing to do.%s\n' "$GREEN" "$RESET"
  exit 0
fi

# --- Apply (only with --yes) -------------------------------------------------

if [[ "$MODE" != "apply" ]]; then
  printf '%sDry-run only.%s Re-run with %s--yes%s to apply auto-fixes.\n' \
    "$YELLOW" "$RESET" "$CYAN" "$RESET"
  exit 0
fi

if [[ "$remove_count" -eq 0 && "$add_count" -eq 0 ]]; then
  printf '%sNothing to apply%s (manual review items only).\n' "$YELLOW" "$RESET"
  exit 0
fi

# Atomic edit: read-modify-write via jq + temp + rename.
TMP_SETTINGS=$(mktemp -t settings-XXXXXX.json)
trap 'rm -f "$TMP_JSON" "$TMP_SETTINGS"' EXIT

# Build jq filter that performs all removals + additions in one pass.
jq_filter='.'

if [[ "$remove_count" -gt 0 ]]; then
  # del(.enabledPlugins["k1"], .enabledPlugins["k2"], ...)
  remove_args=$(echo "$auto_remove" | jq -R . | jq -s 'map("del(.enabledPlugins[\"" + . + "\"])") | join(" | ")' -r)
  jq_filter="$jq_filter | $remove_args"
fi

if [[ "$add_count" -gt 0 ]]; then
  # .enabledPlugins["k1"] = false | .enabledPlugins["k2"] = false | ...
  add_args=$(echo "$auto_add" | jq -R . | jq -s 'map(".enabledPlugins[\"" + . + "\"] = false") | join(" | ")' -r)
  jq_filter="$jq_filter | $add_args"
fi

if ! jq "$jq_filter" "$SETTINGS" >"$TMP_SETTINGS"; then
  echo "ERROR: jq filter failed — settings unchanged" >&2
  exit 2
fi

if ! jq empty "$TMP_SETTINGS" 2>/dev/null; then
  echo "ERROR: post-edit JSON invalid — settings unchanged" >&2
  exit 2
fi

mv "$TMP_SETTINGS" "$SETTINGS"

printf '%sApplied:%s %d removals, %d additions to %s\n' "$GREEN" "$RESET" \
  "$remove_count" "$add_count" "$SETTINGS"

if [[ "$manual_count" -gt 0 ]]; then
  printf '%sManual review still required for %d enabled-true orphans (see above).%s\n' \
    "$RED" "$manual_count" "$RESET"
fi

exit 0
