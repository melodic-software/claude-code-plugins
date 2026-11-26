#!/usr/bin/env bash
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

MAX_CHUNKS=${MAX_CHUNKS:-12}

chunking="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../diff-chunking/diff_chunking.py"
mkdir "$DATA/diff"
status=0
reason=$(python3 -I "$chunking" split "$DATA/diff.patch" "$DATA/diff" "$MAX_DIFF_BYTES" "$MAX_CHUNKS" "$DATA/manifest.txt" "$((MAX_DIFF_BYTES * MAX_CHUNKS))" --cut-lines 2>&1) || status=$?
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
