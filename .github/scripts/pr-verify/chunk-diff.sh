#!/usr/bin/env bash
# Cuts $DATA/diff.patch into the chunks and parts the verifier reads, then
# removes it. Each judgment is given its own parts, and the manifest names
# every file's first part, so it can read across chunks where a change does.
#
# The chunks, pieces, parts and long-line folds are diff_chunking.py's
# (https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/diff-chunking/diff_chunking.py),
# chunks of at most MAX_DIFF_BYTES and parts of at most PART_BYTES and
# PART_LINES. With more than one chunk the manifest lists every file, and each
# piece as `piece <i> of <n>`, with its chunk and first part, in
# $DATA/manifest/part-<n>.txt files of at most PART_BYTES. An empty diff is one
# chunk with one empty part.
#
# A file with a hunk over MAX_DIFF_BYTES with its header, or a diff that needs
# more than MAX_CHUNKS chunks, prints an error naming it and exits 1 with no
# chunk written: the head gets no verdict, and so no fail on size alone.
# shellcheck disable=SC2154 # the step's env sets DATA and the limits
set -euo pipefail

wrap=()
if [[ -n "${LONG_LINE_BYTES+set}" ]]; then
  if [[ ! "$LONG_LINE_BYTES" =~ ^[0-9]+$ ]] || ((LONG_LINE_BYTES < 40)); then
    echo "::error::LONG_LINE_BYTES is not a line length; no verdict for this head"
    exit 1
  fi
  wrap=(--wrap "$LONG_LINE_BYTES")
fi

# The most chunks a head is judged in, and the run's cost guard: each judging
# job in pr-verify.yml has a judge step for every chunk up to this, and a
# timeout that holds them all and the final judge (workflow.test.mjs holds both
# to it). 12 chunks of MAX_DIFF_BYTES hold a 3 MB diff of whole files. Only a
# test sets its own.
MAX_CHUNKS=${MAX_CHUNKS:-12}

chunking="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../diff-chunking/diff_chunking.py"
mkdir "$DATA/diff"
status=0
reason=$(python3 -I "$chunking" split "$DATA/diff.patch" "$DATA/diff" "$MAX_DIFF_BYTES" "$MAX_CHUNKS" "$DATA/manifest.txt" "$((MAX_DIFF_BYTES * MAX_CHUNKS))" 2>&1) || status=$?
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
bytes=$(python3 -I "$chunking" parts "$DATA/diff" "$PART_BYTES" "$PART_LINES" --file-parts "$DATA/file-parts.txt" "${wrap[@]}")
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
