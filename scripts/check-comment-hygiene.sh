#!/usr/bin/env bash
# Exit 0 clean; 1 a violation, each on stderr as <file>:<line>:<kind>:<detail>;
set -uo pipefail

usage() {
  echo "usage: $(basename "$0") <pin-rev> [<file>...]" >&2
  exit 2
}

[[ $# -ge 1 && -n "$1" && "$1" != -* ]] || usage
pin_rev="$1"
shift

WORKFLOW=.github/workflows/pr-require-checks.yml
ACTION_PATH=.github/actions/check-comment-markers
raw_base="${CHECK_COMMENT_HYGIENE_RAW_BASE:-https://raw.githubusercontent.com/melodic-software/ci-workflows}"

top="$(git -C "${CHECK_DATA_ROOT:-.}" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "comment-hygiene: ${CHECK_DATA_ROOT:-.} is not inside a git work tree" >&2
  exit 2
}
cd "$top" || exit 2

pinned="$(git show "$pin_rev:$WORKFLOW" 2>/dev/null)" || {
  echo "comment-hygiene: cannot read $WORKFLOW at $pin_rev" >&2
  exit 2
}
sha="$(sed -nE 's#.*uses:[[:space:]]*melodic-software/ci-workflows/\.github/actions/check-comment-markers@([0-9a-f]{40}|main).*#\1#p' <<<"$pinned")"
sha="${sha%%$'\n'*}"
[[ -n "$sha" ]] || {
  echo "comment-hygiene: no check-comment-markers uses line at main or a SHA in $WORKFLOW at $pin_rev" >&2
  exit 2
}

head_workflow="$(git show "HEAD:$WORKFLOW" 2>/dev/null)" || {
  echo "comment-hygiene: cannot read $WORKFLOW at HEAD" >&2
  exit 2
}
excludes_raw="$(awk '
  function indent(s) { match(s, /^ */); return RLENGTH }
  function emit(s,   n, k, a) { n = split(s, a, " "); for (k = 1; k <= n; k++) print a[k] }
  { line[NR] = $0 }
  END {
    for (i = 1; i <= NR; i++)
      if (line[i] ~ /^[[:space:]]*(- )?uses:[[:space:]]*melodic-software\/ci-workflows\/\.github\/actions\/check-comment-markers@/) { u = i; break }
    if (!u) exit
    for (s = u; s >= 1 && line[s] !~ /^[[:space:]]*- /; s--) continue
    if (s < 1) exit
    sind = indent(line[s])
    for (i = s + 1; i <= NR; i++) {
      if (line[i] ~ /^[[:space:]]*(#|$)/) continue
      if (indent(line[i]) <= sind) break
      if (blk && indent(line[i]) > xind) { emit(line[i]); continue }
      blk = 0
      if (line[i] ~ /^[[:space:]]*exclude:/) {
        xind = indent(line[i]); v = line[i]; sub(/^[[:space:]]*exclude:[[:space:]]*/, "", v)
        if (v == "" || v ~ /^[>|][-+]?[[:space:]]*$/) blk = 1
        else emit(v)
      }
    }
  }
' <<<"$head_workflow")"
declare -a excludes=()
while IFS= read -r tok; do
  tok="${tok//[\"\']/}"
  [[ -n "$tok" ]] || continue
  case "$tok" in
  ':(exclude)'?*) excludes+=("${tok#':(exclude)'}") ;;
  *)
    echo "comment-hygiene: unsupported pathspec in the step's exclude input: $tok" >&2
    exit 2
    ;;
  esac
done <<<"$excludes_raw"

command -v curl >/dev/null 2>&1 || {
  echo "comment-hygiene: curl not installed" >&2
  exit 2
}
dir="$(mktemp -d)" || exit 2
trap 'rm -rf "$dir"' EXIT

fetch() {
  curl -fsSL --connect-timeout 5 --max-time 20 -o "$2" "$raw_base/$sha/$1" 2>/dev/null || {
    echo "comment-hygiene: fetch of $1 at ci-workflows ${sha:0:12} failed" >&2
    exit 2
  }
}

fetch "$ACTION_PATH/action.yml" "$dir/action.yml"
ext_raw="$(awk '
  function indent(s) { match(s, /^ */); return RLENGTH }
  !inx && /^[[:space:]]*extensions:[[:space:]]*$/ { inx = 1; ind = indent($0); next }
  !inx { next }
  /^[[:space:]]*$/ { next }
  indent($0) <= ind { exit }
  blk { if (indent($0) > dind) { print; next } exit }
  /^[[:space:]]*default:/ {
    dind = indent($0); v = $0; sub(/^[[:space:]]*default:[[:space:]]*/, "", v)
    if (v == "" || v ~ /^[>|][-+]?[[:space:]]*$/) { blk = 1; next }
    print v; exit
  }
' "$dir/action.yml")"
ext_raw="${ext_raw//[\"\']/}"
declare -a extensions=()
read -ra extensions <<<"${ext_raw//$'\n'/ }"
((${#extensions[@]})) || {
  echo "comment-hygiene: no extensions default in $ACTION_PATH/action.yml at ci-workflows ${sha:0:12}" >&2
  exit 2
}

selected() {
  local g hit=1
  for g in "${extensions[@]}"; do
    # shellcheck disable=SC2053 # $g is a glob on purpose.
    if [[ "$1" == $g ]]; then
      hit=0
      break
    fi
  done
  ((hit == 0)) || return 1
  for g in ${excludes[@]+"${excludes[@]}"}; do
    # shellcheck disable=SC2053 # $g is a glob on purpose.
    [[ "$1" == $g || "$1" == $g/* ]] && return 1
  done
  return 0
}

declare -a files=()
for f in "$@"; do
  if [[ ! -e "$f" && ! -L "$f" ]]; then
    echo "comment-hygiene: no such file in $top: $f" >&2
    exit 2
  fi
  [[ -f "$f" && ! -L "$f" ]] && selected "$f" && files+=("$f")
done
if ((${#files[@]} == 0)); then
  echo "comment-hygiene: clean, none of the $# files is a code file the gate scans"
  exit 0
fi

fetch "$ACTION_PATH/comment-hygiene-patterns.sh" "$dir/patterns.sh"

scan() (
  # shellcheck source=/dev/null
  source "$1" || exit 2
  shift
  declare -F chp::scan_text >/dev/null || {
    echo "comment-hygiene: the fetched library defines no chp::scan_text" >&2
    exit 2
  }
  local f content hits rc found=0 h
  for f in "$@"; do
    content="$(cat -- "$f")" || exit 2
    [[ -n "$content" ]] || continue
    rc=0
    hits="$(chp::scan_text "$content")" || rc=$?
    case "$rc" in
    0 | 1) [[ $rc == 1 || -n "$hits" ]] || continue ;;
    *)
      echo "comment-hygiene: chp::scan_text exited $rc on $f" >&2
      exit 2
      ;;
    esac
    found=$((found + 1))
    [[ -n "$hits" ]] || echo "$f: chp::scan_text reported a violation without its line" >&2
    while IFS= read -r h; do
      [[ -n "$h" ]] && printf '%s:%s\n' "$f" "$h" >&2
    done <<<"$hits"
  done
  if ((found)); then
    echo "comment-hygiene: violations in $found of ${#files[@]} files (ci-workflows ${sha:0:12}); track the work in the issue tracker, not in a code comment" >&2
    exit 1
  fi
  echo "comment-hygiene: clean over ${#files[@]} files (ci-workflows ${sha:0:12})"
)
scan "$dir/patterns.sh" "${files[@]}"
