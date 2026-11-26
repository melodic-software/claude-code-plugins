#!/usr/bin/env bash
# Exit codes:
#   0  clean
#   1  findings
#   2  environment or usage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)" || exit 2

data_dir="$REPO_ROOT/plugins/engineering-concepts/data"
plugins_dir="$REPO_ROOT/plugins"
indexes=()

usage() {
  printf 'usage: %s [--check] [--data-dir DIR] [--plugins-dir DIR] [--index FILE]...\n' "${0##*/}" >&2
  printf 'Each record is validated by the rules the lookup applies; id, name and alias collisions and a missing owner skill are checked here only, since the lookup tolerates them.\n' >&2
  exit 2
}

while (($# > 0)); do
  case "$1" in
  --check) shift ;;
  --data-dir | --plugins-dir | --index)
    (($# >= 2)) || usage
    case "$1" in
    --data-dir) data_dir="$2" ;;
    --plugins-dir) plugins_dir="$2" ;;
    *) indexes+=("$2") ;;
    esac
    shift 2
    ;;
  *) usage ;;
  esac
done

command -v node >/dev/null 2>&1 || {
  printf 'check-engineering-concepts: node is required\n' >&2
  exit 2
}
for index in ${indexes[@]+"${indexes[@]}"}; do
  [[ -f "$index" ]] || {
    printf 'check-engineering-concepts: index not found: %s\n' "$index" >&2
    exit 2
  }
done

findings=0
finding() {
  printf '%s\n' "$1" >&2
  findings=$((findings + 1))
}

set +e
records="$(node "$SCRIPT_DIR/check-engineering-concepts.mjs" --data-dir "$data_dir" --plugins-dir "$plugins_dir")"
records_status=$?
set -e
case "$records_status" in
0) ;;
1) findings=$((findings + 1)) ;;
*) exit 2 ;;
esac

for index in ${indexes[@]+"${indexes[@]}"}; do
  set +e
  index_findings="$(awk -v f="$index" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    { sub(/\r$/, "") }
    NR == 1 && $0 != "---" { print f ": no frontmatter: the first line must be ---"; bad = 1; fm = 2 }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 && $0 == "---" { fm = 2; if (!seen) { print f ": frontmatter lacks the standards-contract key"; bad = 1 }; next }
    fm == 1 && /^standards-contract:/ {
      seen = 1; v = trim(substr($0, 20)); q = sprintf("%c", 39)
      gsub("^[\"" q "]|[\"" q "]$", "", v)
      if (v !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { print f ": standards-contract \"" v "\" is not a semver (MAJOR.MINOR.PATCH)"; bad = 1 }
      else if (substr(v, 1, index(v, ".") - 1) != "1") { print f ": standards-contract \"" v "\" has a major version other than 1"; bad = 1 }
    }
    fm == 1 && $0 !~ /^[ \t]*$/ && $0 !~ /^standards-contract:/ { print f ":" NR ": frontmatter has another key; standards-contract is the only frontmatter key in v1"; bad = 1 }
    fm == 2 && !table && /^[ \t]*\|/ {
      table = 1; n = split($0, cell, "|"); header = ""
      for (i = 2; i < n || (i == n && trim(cell[i]) != ""); i++) header = header (header == "" ? "" : " | ") trim(cell[i])
      if (header != "Surface | Applies when | File") { print f ": table header is \"" header "\", want \"Surface | Applies when | File\""; bad = 1 }
      next
    }
    table == 1 {
      table = 2
      if ($0 !~ /^[ \t]*\|[ \t:|-]+\|?[ \t]*$/) { print f ": the table header is not followed by a separator row"; bad = 1 }
      next
    }
    table == 2 && /^[ \t]*\|/ {
      row = trim($0); gsub(/\\\|/, "", row); sub(/^\|/, "", row); sub(/\|$/, "", row)
      cells = split(row, cell, "|")
      if (cells != 3) { print f ":" NR ": row has " cells " cells, want 3"; bad = 1 }
    }
    END {
      if (fm == 1) { print f ": frontmatter is never closed with ---"; bad = 1 }
      if (!table) { print f ": no index table with the header | Surface | Applies when | File |"; bad = 1 }
      exit bad
    }' "$index")"
  index_status=$?
  set -e
  if ((index_status != 0)); then
    while IFS= read -r line; do
      finding "$line"
    done <<<"$index_findings"
  fi
done

((findings == 0)) || exit 1
printf 'check-engineering-concepts: ok (%d records, %d indexes)\n' "$records" "${#indexes[@]}"
