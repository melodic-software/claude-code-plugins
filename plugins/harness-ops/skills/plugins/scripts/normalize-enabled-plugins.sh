#!/usr/bin/env bash
# Exit: 0 already-sorted, missing-file, or wrote a reorder (or --report-project);
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

Exit: 0 already sorted, no such --file, or wrote a reorder, or --report-project ran;
1 --check found unsorted keys; 2 usage error, jq missing, or a refused write.
EOF
}

# shellcheck source=../../../lib/opt-value.sh
opt_value_dir="${BASH_SOURCE[0]%/*}"
[[ "$opt_value_dir" != "${BASH_SOURCE[0]}" ]] || opt_value_dir=.
source "$opt_value_dir/../../../lib/opt-value.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --file)
    require_opt_value normalize-enabled-plugins.sh "$@"
    FILE="$2"
    shift 2
    ;;
  --check)
    CHECK=1
    shift
    ;;
  --report-project)
    require_opt_value normalize-enabled-plugins.sh "$@"
    REPORT_PROJECT="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "normalize-enabled-plugins.sh: unknown argument: $1 (see --help)" >&2
    exit 2
    ;;
  esac
done

if [[ -n "$REPORT_PROJECT" && (-n "$FILE" || "$CHECK" -eq 1) ]]; then
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

moved_count() {
  jq -er '(.enabledPlugins // {}) | keys_unsorted as $k
    | reduce range(0; $k | length) as $i ([];
        . + [([range(0; $i) as $j | select($k[$j] < $k[$i]) | .[$j]] | max // 0) + 1])
    | ($k | length) - (max // 0)' "$1"
}

is_sorted() {
  local cur sorted
  cur=$(jq -c '(.enabledPlugins // {}) | keys_unsorted' "$1") || return 2
  sorted=$(jq -c '(.enabledPlugins // {}) | keys' "$1") || return 2
  [[ "$cur" == "$sorted" ]]
}

require_json() {
  if ! jq -e . "$1" >/dev/null 2>&1; then
    echo "refused: unreadable-json ($1)" >&2
    exit 2
  fi
}

if [[ -n "$REPORT_PROJECT" ]]; then
  if [[ ! -f "$REPORT_PROJECT" ]]; then
    echo "project-absent"
    exit 0
  fi
  require_json "$REPORT_PROJECT"
  n=$(key_count "$REPORT_PROJECT")
  set +e
  is_sorted "$REPORT_PROJECT"
  sorted_rc=$?
  set -e
  if [[ "$sorted_rc" -eq 0 ]]; then
    echo "project-sorted keys=$n"
  else
    echo "project-unsorted keys=$n"
  fi
  exit 0
fi

FILE="${FILE:-${FLEET_STATE_USER_SETTINGS:-$HOME/.claude/settings.json}}"

if [[ ! -f "$FILE" ]]; then
  echo "missing-file keys=0"
  exit 0
fi

require_json "$FILE"
n=$(key_count "$FILE")
set +e
is_sorted "$FILE"
sorted_rc=$?
set -e
if [[ "$sorted_rc" -eq 0 ]]; then
  echo "already-sorted keys=$n"
  exit 0
fi

moved=$(moved_count "$FILE")
if [[ "$CHECK" -eq 1 ]]; then
  echo "would-normalize moved=$moved keys=$n"
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
trap 'rm -rf "$workdir"' EXIT

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

if ! jq -S . "$FILE" >"$before_sorted" || ! jq -S . "$tmp" >"$after_sorted"; then
  echo "refused: unreadable-json ($FILE)" >&2
  exit 2
fi
if ! jq -en --slurpfile before "$before_sorted" --slurpfile after "$after_sorted" \
  '$before == $after' >/dev/null; then
  echo "refused: semantic-diff (reorder would change more than key order)" >&2
  exit 2
fi

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

echo "normalized moved=$moved keys=$n"
exit 0
