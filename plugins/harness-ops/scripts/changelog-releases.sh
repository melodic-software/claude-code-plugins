#!/usr/bin/env bash
# changelog-releases.sh: the one parser of the Claude Code changelog page's release markup.
#
# Usage:
#   changelog-releases.sh [<file>|-]                 rows, one per release and per item
#   changelog-releases.sh --blocks <A..B|X> [<file>|-]   the raw lines of those releases
#
# Reads the page body (a fetch-docs.sh copy, or stdin when the file is omitted or -).
# A release opens at either form of release marker the page has used, a
# `<Update label="X.Y.Z" ...>` line or a line that is only `**X.Y.Z**`, and runs to
# `</Update>`, the next release marker, or end of input. An item is a `*` or `-`
# bullet line inside a release; bold group headings are not items.
#
# Rows, tab-separated, in page order:
#   release<TAB><X.Y.Z>
#   item<TAB><X.Y.Z><TAB><bullet text>
# --blocks prints each release in range (inclusive, v prefix optional) from its marker
# line to its last line, in page order.
#
# Exit: 0 parsed (zero rows when the body has no release marker); 3 invalid argument
# or unreadable file.

set -uo pipefail

err() { printf 'ERROR: %s\n' "$*" >&2; }
VERSION_RE='[0-9]+\.[0-9]+\.[0-9]+'

lo=""
hi=""
if [[ "${1:-}" == "--blocks" ]]; then
  if [[ "${2:-}" =~ ^v?($VERSION_RE)\.\.v?($VERSION_RE)$ ]]; then
    lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[2]}"
  elif [[ "${2:-}" =~ ^v?($VERSION_RE)$ ]]; then
    lo="${BASH_REMATCH[1]}" hi="${BASH_REMATCH[1]}"
  else
    err "--blocks takes A..B or X, versions as X.Y.Z with an optional v prefix; got: ${2:-}"
    exit 3
  fi
  shift 2
fi
file="${1:--}"
if [[ $# -gt 1 || ("$file" != "-" && ! -r "$file") ]]; then
  err "usage: changelog-releases.sh [--blocks <A..B|X>] [<file>|-]"
  exit 3
fi

awk -v lo="$lo" -v hi="$hi" '
  function vcmp(a, b,   A, B, i) {
    split(a, A, "."); split(b, B, ".")
    for (i = 1; i <= 3; i++) {
      if (A[i] + 0 < B[i] + 0) return -1
      if (A[i] + 0 > B[i] + 0) return 1
    }
    return 0
  }
  function open_release(ver) {
    v = ver
    keep = lo != "" && vcmp(v, lo) >= 0 && vcmp(v, hi) <= 0
    if (lo == "") print "release\t" v
  }
  { sub(/\r$/, "") }
  /<Update label="[0-9]+\.[0-9]+\.[0-9]+"/ {
    match($0, /label="[0-9]+\.[0-9]+\.[0-9]+"/)
    open_release(substr($0, RSTART + 7, RLENGTH - 8))
    if (keep) print
    next
  }
  /^\*\*[0-9]+\.[0-9]+\.[0-9]+\*\*[[:space:]]*$/ {
    ver = $0
    gsub(/[*[:space:]]/, "", ver)
    open_release(ver)
    if (keep) print
    next
  }
  /^[[:space:]]*<\/Update>/ {
    if (keep) print
    v = ""; keep = 0
    next
  }
  v == "" { next }
  keep { print; next }
  lo == "" && /^[[:space:]]*[*-][[:space:]]+/ {
    text = $0
    sub(/^[[:space:]]*[*-][[:space:]]+/, "", text)
    print "item\t" v "\t" text
  }
' "$file"
