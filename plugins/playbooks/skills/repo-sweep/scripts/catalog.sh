#!/usr/bin/env bash
# Parse a repo-sweep catalog (format: ../catalogs/hygiene.md is the reference instance).
#
#   catalog.sh <catalog-file>                 one TSV row per entry, in file order:
#                                             id, phase, skills, args, checked, issue, applies-when
#   catalog.sh --override <id> <catalog-file> that entry's "#### Override" block (empty if none)
#   catalog.sh --notes <id> <catalog-file>    that entry's "#### Notes" block (empty if none)
#
# phase is the full "## ..." heading text. Missing keys print as empty fields.
# Exit: 0 ok; 1 duplicate id, entry with no skill, or unknown id (nothing on stdout); 2 usage.
set -euo pipefail

block="" id="" file=""
while (($#)); do
  case $1 in
  --override | --notes)
    block=${1#--}
    id=${2-}
    shift 2 || break
    ;;
  *)
    file=$1
    shift
    ;;
  esac
done
if [[ -z $file || ! -f $file || (-n $block && -z $id) ]]; then
  printf 'usage: catalog.sh [--override <id> | --notes <id>] <catalog-file>\n' >&2
  exit 2
fi

awk -v block="$block" -v want="$id" '
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
{ sub(/\r$/, "") }
/^### / {
  n++; ids[n] = trim(substr($0, 5)); ph[n] = phase; cur = n; blk = ""
  if (ids[n] in seen) { printf "catalog.sh: duplicate id: %s (line %d)\n", ids[n], NR > "/dev/stderr"; bad = 1 }
  seen[ids[n]] = 1
  next
}
/^#### / { if (cur) blk = tolower(trim(substr($0, 6))); next }
/^## / { phase = trim(substr($0, 4)); cur = 0; next }
/^#/ { cur = 0; next }
cur && blk == "" && /^- [a-z-]+:/ {
  i = index($0, ":"); v[cur, substr($0, 3, i - 3)] = trim(substr($0, i + 1)); next
}
cur && blk != "" { k = ++len[cur, blk]; txt[cur, blk, k] = $0 }
END {
  for (i = 1; i <= n; i++)
    if (v[i, "skill"] == "") { printf "catalog.sh: entry %s has no skill\n", ids[i] > "/dev/stderr"; bad = 1 }
  if (bad) exit 1
  if (block == "") {
    OFS = "\t"
    for (i = 1; i <= n; i++) print ids[i], ph[i], v[i, "skill"], v[i, "args"], v[i, "checked"], v[i, "issue"], v[i, "applies-when"]
    exit 0
  }
  for (i = 1; i <= n && ids[i] != want; i++) ;
  if (i > n) { printf "catalog.sh: unknown id: %s\n", want > "/dev/stderr"; exit 1 }
  first = 1; last = len[i, block]
  while (first <= last && txt[i, block, first] ~ /^[ \t]*$/) first++
  while (last >= first && txt[i, block, last] ~ /^[ \t]*$/) last--
  for (k = first; k <= last; k++) print txt[i, block, k]
}' "$file"
