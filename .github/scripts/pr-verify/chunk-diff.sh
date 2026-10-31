#!/usr/bin/env bash
# Cuts $DATA/diff.patch into the chunks and parts the verifier reads, then
# removes it. Each judgment is given its own parts, and the manifest names
# every file's first part, so it can read across chunks where a change does.
#
# Each chunk holds whole files, at most MAX_DIFF_BYTES, in diff order
# (../pr-review-main/split-diff.py), and with more than one chunk manifest.txt
# lists every file with its chunk, in $DATA/manifest/part-<n>.txt files of at
# most PART_BYTES. Each chunk is cut into
# $DATA/diff/chunk-<k>/part-<n>.patch files of at most PART_BYTES and PART_LINES.
# Read may cut a long line short, so a line over LONG_LINE_BYTES continues on
# lines that start `\ continued: `, which no line of a diff does, each on the
# side of the line it continues, and every byte of the diff reaches a whole
# Read. An empty diff is one chunk with one empty part.
#
# A file over MAX_DIFF_BYTES, or a diff that needs more than MAX_CHUNKS chunks,
# prints an error naming it and exits 1 with no chunk written: the head gets no
# verdict, and so no fail on size alone.
# shellcheck disable=SC2154 # the step's env sets DATA and the limits
set -euo pipefail

# A fold takes a mark and a byte each line, or it never ends.
if [[ ! "$LONG_LINE_BYTES" =~ ^[0-9]+$ ]] || ((LONG_LINE_BYTES < 40)); then
  echo "::error::LONG_LINE_BYTES is not a line length; no verdict for this head"
  exit 1
fi

# The most chunks a head is judged in, and the run's cost guard: each judging
# job in pr-verify.yml has a judge step for every chunk up to this, and a
# timeout that holds them all and the final judge (workflow.test.mjs holds both
# to it). 12 chunks of MAX_DIFF_BYTES hold a 3 MB diff of whole files. Only a
# test sets its own.
MAX_CHUNKS=${MAX_CHUNKS:-12}

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir "$DATA/diff"
status=0
reason=$(python3 -I "$here/../pr-review-main/split-diff.py" "$DATA/diff.patch" "$DATA/diff" "$MAX_DIFF_BYTES" "$MAX_CHUNKS" "$DATA/manifest.txt" "$((MAX_DIFF_BYTES * MAX_CHUNKS))" 2>&1) || status=$?
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
  LC_ALL=C awk -v dir="$dir" -v rel="diff/chunk-$k" -v list="$DATA/file-parts.txt" -v maxb="$PART_BYTES" -v maxl="$PART_LINES" -v wrap="$LONG_LINE_BYTES" '
    function put(text) {
      len = length(text) + 1
      if (n == 0 || b + len > maxb || l >= maxl) { if (f) close(f); f = sprintf("%s/part-%03d.patch", dir, ++n); b = 0; l = 0 }
      print text > f; b += len; l++
      if (header) { print sprintf("%s/part-%03d.patch", rel, n) >> list; header = 0 }
    }
    # The header test reads the line as the diff has it, so a continuation
    # cannot pose as a file. A cut never falls inside a UTF-8 character, of
    # at most three continuation bytes, so a run of stray ones still folds at
    # the cap. A continuation takes the side of the line it continues.
    { header = index($0, "diff --git ") == 1
      rest = $0; mark = ""
      while (length(mark) + length(rest) > wrap) {
        at = wrap - length(mark)
        for (back = 0; back < 3 && at > 1; back++) {
          next_byte = substr(rest, at + 1, 1)
          if (next_byte < "\200" || next_byte >= "\300") break
          at--
        }
        put(mark substr(rest, 1, at))
        rest = substr(rest, at + 1); mark = "\\ continued: "
      }
      put(mark rest) }' "$dir.patch"
  if [[ ! -s "$dir.patch" ]]; then
    : >"$dir/part-001.patch"
  fi
  bytes="$bytes${bytes:+,}$(wc -c <"$dir.patch")"
  rm "$dir.patch"
done
rm "$DATA/diff.patch"

# Each manifest line, in file order, gains the part its file starts in, and
# the list is cut into files one Read returns whole. Each line is shorter than
# its file's lines in the diff, so the cap above never cuts the list.
paths=0
if [[ -f "$DATA/manifest.txt" ]]; then
  mkdir "$DATA/manifest"
  awk 'NR == FNR { part[FNR] = $0; next } { sub(/^chunk [0-9]+ /, "&" part[FNR] " "); print }' \
    "$DATA/file-parts.txt" "$DATA/manifest.txt" |
    LC_ALL=C awk -v dir="$DATA/manifest" -v maxb="$PART_BYTES" '
      { len = length($0) + 1
        if (n == 0 || b + len > maxb) { if (f) close(f); f = sprintf("%s/part-%03d.txt", dir, ++n); b = 0 }
        print > f; b += len }'
  paths=$(wc -l <"$DATA/manifest.txt")
  rm "$DATA/manifest.txt"
fi
rm -f "$DATA/file-parts.txt"

echo "chunks=$chunks" >>"$GITHUB_OUTPUT"
echo "::notice title=pr-verify chunks::pr=$PR_NUMBER chunks=$chunks bytes=$bytes manifest_paths=$paths"
