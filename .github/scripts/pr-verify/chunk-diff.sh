#!/usr/bin/env bash
# Cuts $DATA/diff.patch into the chunks and parts the verifier reads, then
# removes it, so each judgment reads only its own parts.
#
# Each chunk holds whole files, at most MAX_DIFF_BYTES, in diff order
# (../pr-review-main/split-diff.py), and with more than one chunk manifest.txt
# lists every file with its chunk. Each chunk is cut into
# $DATA/diff/chunk-<k>/part-<n>.patch files of at most PART_BYTES and PART_LINES;
# a line longer than a part stays whole in its own, for the verifier to name as
# unreadable. An empty diff is one chunk with one empty part.
#
# A file over MAX_DIFF_BYTES, or a diff that needs more than MAX_CHUNKS chunks,
# prints an error naming it and exits 1 with no chunk written: the head gets no
# verdict, and so no fail on size alone.
# shellcheck disable=SC2154 # the step's env sets DATA and the limits
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir "$DATA/diff"
status=0
reason=$(python3 -I "$here/../pr-review-main/split-diff.py" "$DATA/diff.patch" "$DATA/diff" "$MAX_DIFF_BYTES" "$MAX_CHUNKS" "$DATA/manifest.txt" "$PART_BYTES" 2>&1) || status=$?
if [[ "$status" -eq 3 ]]; then
  echo "::error::no verdict for this head: the diff is $(wc -c <"$DATA/diff.patch") bytes; ${reason#split-diff: }"
  exit 1
elif [[ "$status" -ne 0 ]]; then
  echo "::error::the diff did not split into chunks; no verdict for this head"
  exit 1
fi

chunks=$(find "$DATA/diff" -name 'chunk-*.patch' | wc -l)
if [[ "$chunks" -eq 0 ]]; then
  chunks=1
  : >"$DATA/diff/chunk-1.patch"
fi

bytes=
for k in $(seq "$chunks"); do
  dir="$DATA/diff/chunk-$k"
  mkdir "$dir"
  LC_ALL=C awk -v dir="$dir" -v maxb="$PART_BYTES" -v maxl="$PART_LINES" '
    { len = length($0) + 1
      if (n == 0 || b + len > maxb || l >= maxl) { if (f) close(f); f = sprintf("%s/part-%03d.patch", dir, ++n); b = 0; l = 0 }
      print > f; b += len; l++ }' "$dir.patch"
  if [[ ! -s "$dir.patch" ]]; then
    : >"$dir/part-001.patch"
  fi
  bytes="$bytes${bytes:+,}$(wc -c <"$dir.patch")"
  rm "$dir.patch"
done
rm "$DATA/diff.patch"

echo "chunks=$chunks" >>"$GITHUB_OUTPUT"
paths=0
if [[ -f "$DATA/manifest.txt" ]]; then paths=$(grep -c '^chunk ' "$DATA/manifest.txt" || true); fi
echo "::notice title=pr-verify chunks::pr=$PR_NUMBER chunks=$chunks bytes=$bytes manifest_paths=$paths"
