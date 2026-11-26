#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
splice-assets.sh: splice the workspace assets into one HTML lesson, in place.

Usage: splice-assets.sh <lesson.html> <assets-dir>
       splice-assets.sh --help | -h

  <lesson.html>   the lesson file to rewrite, a readable and writable regular file
  <assets-dir>    the workspace assets directory holding lesson.css and quiz.js

A line containing `/* SPLICE:STYLE */` is replaced by <assets-dir>/lesson.css and a
line containing `/* SPLICE:QUIZ */` by <assets-dir>/quiz.js. Only the markers present
in the lesson are replaced, and an absent marker makes no demand on its asset file.
A marker line is replaced whole, so it must hold the marker alone, whitespace aside;
a marker sharing its line with anything else is refused.

Exits 1 when a present marker's asset is missing, not a regular file, unreadable, or
empty, when a marker occurs more than once, when a marker shares its line, when an
asset read fails, or when the build fails; the lesson is left byte-identical. Exits 2
on a usage error.
EOF
}

usage_error() {
  echo "splice-assets.sh: $1" >&2
  usage >&2
  exit 2
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

[[ $# -eq 2 ]] || usage_error "expected <lesson.html> <assets-dir>; got $# argument(s)"

lesson="$1"
assets="$2"

[[ -f "$lesson" && -r "$lesson" && -w "$lesson" ]] ||
  usage_error "<lesson.html> is not a readable, writable regular file: $lesson"
[[ -d "$assets" ]] || usage_error "<assets-dir> is not a directory: $assets"

markers=('/* SPLICE:STYLE */' '/* SPLICE:QUIZ */')
asset_names=('lesson.css' 'quiz.js')

for i in 0 1; do
  marker="${markers[$i]}"
  count=$(($(grep -oF -- "$marker" "$lesson" | wc -l)))
  if [[ "$count" -gt 1 ]]; then
    echo "splice-assets.sh: marker $marker occurs $count times in $lesson; expected at most 1" >&2
    exit 1
  fi
  if [[ "$count" -eq 1 ]]; then
    line=$(grep -F -- "$marker" "$lesson")
    if [[ "${line//[[:space:]]/}" != "${marker//[[:space:]]/}" ]]; then
      echo "splice-assets.sh: marker $marker shares its line in $lesson with other text; a marker line must hold the marker alone. The line is: $line" >&2
      exit 1
    fi
    asset="$assets/${asset_names[$i]}"
    [[ -f "$asset" && -r "$asset" && -s "$asset" ]] || {
      echo "splice-assets.sh: marker $marker needs a readable non-empty asset file: $asset" >&2
      exit 1
    }
  fi
done

lesson_dir=$(dirname -- "$lesson")
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd) || {
  echo "splice-assets.sh: could not resolve the directory holding this script" >&2
  exit 1
}

tmp=""
trap 'if [[ -n "$tmp" ]]; then rm -f -- "$tmp"; fi' EXIT

tmp=$(mktemp "$lesson_dir/.splice-assets.XXXXXX") || {
  echo "splice-assets.sh: could not create a temp file beside $lesson" >&2
  exit 1
}

A="$assets" awk -v BINMODE=3 -f "$script_dir/splice-assets.awk" "$lesson" >"$tmp" || {
  echo "splice-assets.sh: building the spliced lesson failed (awk; any reason it named is above); $lesson is unchanged" >&2
  exit 1
}

cat -- "$tmp" >"$lesson" || {
  echo "splice-assets.sh: writing the spliced lesson back over $lesson failed" >&2
  exit 1
}

exit 0
