#!/usr/bin/env bash
# Reorder `enabledPlugins` keys alphabetically in a user-scope settings file.
#
#   normalize-enabled-plugins.sh [--file <path>] [--check]
#   normalize-enabled-plugins.sh --report-project <path>
#
# Claude Code's settings writer appends each newly installed `enabledPlugins`
# key at the end of the map. The rest of the map is alphabetical, so every
# `sync` that installs something leaves an unsorted tail that never self-heals.
# There is no `claude plugin` verb that reorders the map, so this script does
# a strict key-reorder write of the user-scope file only.
#
# Invariants:
#   - User scope only. `--file` defaults to ~/.claude/settings.json
#     (overridable via FLEET_STATE_USER_SETTINGS, same as fleet-state.sh).
#   - `--report-project` inspects a committed project settings file and NEVER
#     writes it. `converge` is the only action permitted to touch that file.
#   - Keys and values stay byte-identical; only key order changes. If a
#     semantic diff appears (jq -S before != jq -S after), the write is
#     aborted rather than applied.
#   - Permission denial and parse failure are loud (exit 2), never silent.
#
# Exit: 0 already-sorted or wrote a reorder (or --report-project and sorted);
#       1 --check found unsorted keys (would normalize; no write);
#       2 usage / refused (parse, semantic-diff, write-denied, project write).
set -euo pipefail

FILE=""
CHECK=0
REPORT_PROJECT=""

usage() {
  cat <<'EOF'
normalize-enabled-plugins.sh — alphabetize enabledPlugins keys (user scope).

Usage:
  normalize-enabled-plugins.sh [--file <path>] [--check]
  normalize-enabled-plugins.sh --report-project <path>

--file defaults to $FLEET_STATE_USER_SETTINGS or ~/.claude/settings.json.
--check reports whether a reorder is needed without writing.
--report-project inspects a project-scope settings file and never writes it.
EOF
}

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "normalize-enabled-plugins.sh: $opt requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --file)
    require_opt_value "$@"
    FILE="$2"
    shift 2
    ;;
  --check)
    CHECK=1
    shift
    ;;
  --report-project)
    require_opt_value "$@"
    REPORT_PROJECT="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "normalize-enabled-plugins.sh: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

if [[ -n "$REPORT_PROJECT" && ( -n "$FILE" || "$CHECK" -eq 1 ) ]]; then
  echo "normalize-enabled-plugins.sh: --report-project cannot be combined with --file or --check" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "normalize-enabled-plugins.sh: jq is required" >&2
  exit 2
fi

key_count() {
  jq -er '(.enabledPlugins // {}) | keys_unsorted | length' "$1"
}

is_sorted() {
  local cur sorted
  cur=$(jq -c '(.enabledPlugins // {}) | keys_unsorted' "$1") || return 2
  sorted=$(jq -c '(.enabledPlugins // {}) | keys' "$1") || return 2
  [[ "$cur" == "$sorted" ]]
}

report_project() {
  local path="$1" n sorted_rc
  if [[ ! -f "$path" ]]; then
    echo "project-absent"
    return 0
  fi
  if ! jq -e . "$path" >/dev/null 2>&1; then
    echo "refused: unreadable-json ($path)" >&2
    exit 2
  fi
  n=$(key_count "$path")
  sorted_rc=0
  is_sorted "$path" || sorted_rc=$?
  if [[ "$sorted_rc" -eq 0 ]]; then
    echo "project-sorted keys=$n"
    return 0
  fi
  echo "project-unsorted keys=$n"
  return 0
}

if [[ -n "$REPORT_PROJECT" ]]; then
  report_project "$REPORT_PROJECT"
  exit 0
fi

FILE="${FILE:-${FLEET_STATE_USER_SETTINGS:-$HOME/.claude/settings.json}}"

if [[ -z "$FILE" ]]; then
  echo "normalize-enabled-plugins.sh: no settings file resolved" >&2
  exit 2
fi

if [[ ! -f "$FILE" ]]; then
  echo "already-sorted keys=0"
  exit 0
fi

if ! jq -e . "$FILE" >/dev/null 2>&1; then
  echo "refused: unreadable-json ($FILE)" >&2
  exit 2
fi

n=$(key_count "$FILE")
sorted_rc=0
is_sorted "$FILE" || sorted_rc=$?
if [[ "$sorted_rc" -eq 0 ]]; then
  echo "already-sorted keys=$n"
  exit 0
fi

if [[ "$CHECK" -eq 1 ]]; then
  echo "would-normalize keys=$n"
  exit 1
fi

if [[ ! -w "$FILE" ]]; then
  echo "refused: write-denied ($FILE is not writable)" >&2
  exit 2
fi

workdir="$(mktemp -d)" || {
  echo "refused: write-denied (could not create a temp directory)" >&2
  exit 2
}
tmp="$workdir/rewritten.json"
before_sorted="$workdir/before.json"
after_sorted="$workdir/after.json"
# shellcheck disable=SC2064
trap 'rm -rf "$workdir"' EXIT

# Preserve compact vs pretty and CRLF vs LF so a one-key reorder does not
# churn unrelated lines or line endings.
jq_indent=(--indent 2)
line_count="$(tr -d '\r' <"$FILE" | wc -l)"
if [[ ! -s "$FILE" || "$line_count" -le 1 ]]; then
  jq_indent=(-c)
fi
crlf=0
if grep -q $'\r' "$FILE"; then
  crlf=1
fi

if ! jq "${jq_indent[@]}" \
  'if has("enabledPlugins") then .enabledPlugins = (.enabledPlugins | to_entries | sort_by(.key) | from_entries) else . end' \
  "$FILE" >"$tmp"; then
  echo "refused: unreadable-json ($FILE)" >&2
  exit 2
fi
if [[ "$crlf" -eq 1 ]]; then
  tmp_crlf="$workdir/rewritten.crlf.json"
  sed 's/$/\r/' "$tmp" >"$tmp_crlf"
  tmp="$tmp_crlf"
fi

# Semantic equality of the whole document, key-order-insensitive. A rewrite
# that changed a value, dropped a key, or invented enabledPlugins when absent
# must not land. Real temp files rather than process substitution: a
# native-Windows jq does not reliably read Git Bash /dev/fd paths.
# jq -e/--exit-status makes a false comparison fail the `if` — without it
# the guard is dead code (jq exits 0 for both true and false).
if ! jq -S . "$FILE" >"$before_sorted" || ! jq -S . "$tmp" >"$after_sorted"; then
  echo "refused: unreadable-json ($FILE)" >&2
  exit 2
fi
if ! jq -en --slurpfile before "$before_sorted" --slurpfile after "$after_sorted" \
  '$before == $after' >/dev/null; then
  echo "refused: semantic-diff (reorder would change more than key order)" >&2
  exit 2
fi

# Atomic replace: write a sibling then mv so a crash cannot truncate the
# live settings file. Preserve the original mode when chmod --reference works.
sib="$FILE.norm.$$"
if ! cat "$tmp" >"$sib"; then
  echo "refused: write-denied (could not write $sib)" >&2
  rm -f "$sib"
  exit 2
fi
chmod --reference="$FILE" "$sib" 2>/dev/null || true
if ! mv -f "$sib" "$FILE"; then
  echo "refused: write-denied (could not replace $FILE)" >&2
  rm -f "$sib"
  exit 2
fi

echo "normalized keys=$n"
exit 0
