#!/usr/bin/env bash
# check-corpus-grid.sh: every adapter has a GRID.md row, and every `pair` cell
# has a bad and a good corpus file for its rule.
#
# Usage: check-corpus-grid.sh [<corpus-dir> [<adapters-dir>]]
# Exit: 0 the grid holds; 1 a missing row, file or malformed cell.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS="${1:-$SCRIPT_DIR/../evals/fixtures/corpus}"
ADAPTERS="${2:-$SCRIPT_DIR/../adapters}"
GRID="$CORPUS/GRID.md"
bad=0
problem() {
  printf 'check-corpus-grid: %s\n' "$1" >&2
  bad=1
}

[[ -f "$GRID" ]] || {
  problem "no grid at $GRID"
  exit 1
}

# has_header <dir> <header>: a corpus file in <dir> carries the header line.
has_header() {
  [[ -d "$1" ]] && grep -rlqE "(^|[^a-z-])$2([^a-z-]|$)" "$1"
}

rules=()
declare -A rowed=()
# Only the table whose header's first cell is Adapter is the grid; any other
# table in GRID.md (Pocock examples, planted tests) is prose for readers. A
# line that does not start with | ends a table.
in_grid=0
while IFS= read -r line; do
  if [[ "$line" != '|'* ]]; then
    in_grid=0
    continue
  fi
  IFS='|' read -ra cells <<<"$line"
  for i in "${!cells[@]}"; do
    cells[i]="$(printf '%s' "${cells[i]}" | sed 's/^ *//; s/ *$//')"
  done
  adapter="${cells[1]}"
  case "$adapter" in
  Adapter)
    in_grid=1
    rules=("${cells[@]:2}")
    continue
    ;;
  ---*) continue ;;
  *) ;;
  esac
  ((in_grid)) || continue
  rowed[$adapter]=1
  for i in "${!rules[@]}"; do
    cell="${cells[i + 2]:-}" rule="${rules[i]}"
    case "$cell" in
    pair)
      has_header "$CORPUS/$adapter/bad" "expect: $rule" || problem "$adapter: pair cell for $rule has no bad file with 'expect: $rule'"
      has_header "$CORPUS/$adapter/good" "good-for: $rule" || problem "$adapter: pair cell for $rule has no good file with 'good-for: $rule'"
      ;;
    'n/a: '?*) ;;
    *) problem "$adapter: cell for $rule is '$cell', not 'pair' or 'n/a: <reason>'" ;;
    esac
  done
done <"$GRID"

[[ ${#rules[@]} -gt 0 ]] || problem "GRID.md has no '| Adapter |' header row"
for f in "$ADAPTERS"/*.yaml; do
  id="$(sed -n 's/^id:[[:space:]]*//p' "$f")"
  [[ -n "${rowed[$id]:-}" ]] || problem "adapter $id has no GRID.md row"
done
exit "$bad"
