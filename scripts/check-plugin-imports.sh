#!/usr/bin/env bash
# Enforces the boundary rule "a plugin's code never loads a file from a sibling
# plugin", recorded under `## Boundary rules` in
# docs/conventions/architecture/README.md.
#
#   scripts/check-plugin-imports.sh
#
# Every tracked shell, Node, Python and PowerShell file under plugins/<a>/, and
# every tracked extensionless file starting with `#!`, is read for relative paths in a load position. Each is resolved against the
# file's own directory, and one that lands in plugins/<b>/, b != a, is a crossing:
#   - a path after a variable or this-file anchor: $SCRIPT_DIR/../x,
#     ${HERE}/../x, $(dirname "$0")/../x, ${BASH_SOURCE%/*}/../x,
#     $PSScriptRoot/../x, __dirname/../x, import.meta.dirname/../x;
#   - a JS or TS module specifier: from "../x", import("../x"), require("../x");
#   - literal arguments after an anchor in join, resolve or Join-Path:
#     join(here, "..", "x"), os.path.join(HERE, "../x"), Join-Path $PSScriptRoot '..\x';
#   - pathlib: Path(__file__).parents[2] / "x", HERE.parent / "x".
# A variable named *PLUGIN_ROOT or *PLUGIN_DIR is taken to be the plugin's root, any
# other variable anchor the file's directory. Comment lines, and path
# strings with no anchor (globs, fixture data, schema text), are not crossings.
#
# scripts/plugin-imports-exceptions.txt lists accepted crossings, one line per
# file and sibling plugin: `<path> <sibling> <YYYY-MM-DD> <reason>`. A crossing it
# does not list fails, and so does a listed one that no longer crosses.
#
# Exit codes and streams follow the check-script contract in scripts/README.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# CHECK_DATA_ROOT: the tree to check, when it is not the one holding this
# script (scripts/check-affected.sh run from the pre-push hook's merge-base copy).
cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

if (($#)); then
  echo "usage: $(basename "$0")" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "check-plugin-imports: git not found on PATH" >&2
  exit 2
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-plugin-imports: $PWD is not a git work tree" >&2
  exit 2
fi

RULE="a plugin's code never loads a file from a sibling plugin"
exceptions=scripts/plugin-imports-exceptions.txt

# norm <dir> <rel>: sets REPLY to <dir>/<rel> with `.` and `..` segments folded.
norm() {
  local rest="$1/$2/" p k=0
  local -a out=()
  while [[ -n "$rest" ]]; do
    p="${rest%%/*}"
    rest="${rest#*/}"
    case "$p" in
    "" | .) ;;
    ..)
      if ((k)) && [[ "${out[k - 1]}" != .. ]]; then
        k=$((k - 1))
      else
        out[k]=..
        k=$((k + 1))
      fi
      ;;
    *)
      out[k]="$p"
      k=$((k + 1))
      ;;
    esac
  done
  REPLY=""
  for ((p = 0; p < k; p++)); do REPLY+="${REPLY:+/}${out[p]}"; done
}

# up <n>: sets REPLY to n `..` segments joined by `/`.
up() {
  local i
  REPLY=.
  for ((i = 0; i < $1; i++)); do REPLY+=/..; done
}

# The token after an anchor ends at whitespace, a quote, or a shell or code delimiter.
path_chars='[^][:space:]"'"'"'`;)|&<>,}$]*'
re_anchor='(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\$\{[A-Za-z_][A-Za-z0-9_]*%/\*\}|\$\(dirname[^)]*\)|__dirname|import\.meta\.dirname)(/'"$path_chars"')'
re_spec='(from|require\(|import\(|import)[[:space:]]*["'"'"'`](\.\.?/[^"'"'"'`]*)["'"'"'`]'
# shellcheck disable=SC2016  # regex text: the `$` is matched, never expanded
re_join='(join|resolve|Join-Path)[[:space:]]*\(?[[:space:]]*(-Path[[:space:]]+)?[$A-Za-z_][$A-Za-z0-9_.]*(([[:space:]]*,?[[:space:]]*(-ChildPath[[:space:]]+)?["'"'"'][^"'"'"']*["'"'"'])+)'
re_lit='["'"'"']([^"'"'"']*)["'"'"']'
re_pathlib='(Path\(__file__\)(\.resolve\(\))?|[A-Za-z_][A-Za-z0-9_]*)(\.parents\[([0-9]+)\]|(\.parent)+)(([[:space:]]*/[[:space:]]*["'"'"'][^"'"'"']+["'"'"'])+)'

declare -a crossings=()
declare -A crossing_keys=()

# consider <file> <line no> <rel> [<base>]: records a crossing when <rel>, resolved
# against <base> (default <file>'s directory), lands in another plugin's directory.
consider() {
  local file="$1" n="$2" rel="$3" own sib
  [[ "$rel" == *..* ]] || return 0
  own="${file#plugins/}"
  own="${own%%/*}"
  norm "${4:-${file%/*}}" "$rel"
  [[ "$REPLY" == plugins/?* ]] || return 0
  sib="${REPLY#plugins/}"
  sib="${sib%%/*}"
  [[ "$sib" != "$own" && -d "plugins/$sib" ]] || return 0
  crossings+=("$file	$n	$sib	$REPLY")
  crossing_keys["$file $sib"]=1
}

# literals <text>: sets REPLY to the quoted literals in <text> joined by `/`.
literals() {
  local text="$1"
  REPLY=.
  while [[ "$text" =~ $re_lit ]]; do
    REPLY+="/${BASH_REMATCH[1]}"
    text="${text#*"${BASH_REMATCH[0]}"}"
  done
}

scan_line() {
  local file="$1" n="$2" line="$3" ext="${1##*.}" s rest base ups own whole
  s="${line#"${line%%[![:space:]]*}"}"
  case "$ext" in
  mjs | js | cjs | jsx | ts | mts | cts | tsx)
    [[ "$s" == //* || "$s" == \** || "$s" == /\** ]] && return 0
    ;;
  ps1 | psm1)
    [[ "$s" == \#* || "$s" == '<#'* ]] && return 0
    line="${line//\\//}"
    ;;
  *) [[ "$s" == \#* ]] && return 0 ;;
  esac

  # Each form is tried only on a line holding its keyword: a regex match costs far more.
  rest="$line"
  while [[ "$rest" == *'$'* || "$rest" == *__dirname* || "$rest" == *import.meta.dirname* ]] && [[ "$rest" =~ $re_anchor ]]; do
    whole="${BASH_REMATCH[0]}"
    case "${BASH_REMATCH[1]}" in
    *PLUGIN_ROOT | *PLUGIN_ROOT\} | *PLUGIN_DIR | *PLUGIN_DIR\})
      own="${file#plugins/}"
      consider "$file" "$n" "${BASH_REMATCH[2]}" "plugins/${own%%/*}"
      ;;
    *) consider "$file" "$n" "${BASH_REMATCH[2]}" ;;
    esac
    rest="${rest#*"$whole"}"
  done

  case "$ext" in
  mjs | js | cjs | jsx | ts | mts | cts | tsx)
    rest="$line"
    while [[ "$rest" == *from* || "$rest" == *require* || "$rest" == *import* ]] && [[ "$rest" =~ $re_spec ]]; do
      consider "$file" "$n" "${BASH_REMATCH[2]}"
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
    ;;
  *) ;;
  esac

  rest="$line"
  while [[ "$rest" == *join* || "$rest" == *resolve* || "$rest" == *Join-Path* ]] && [[ "$rest" =~ $re_join ]]; do
    whole="${BASH_REMATCH[0]}"
    literals "${BASH_REMATCH[3]}"
    consider "$file" "$n" "$REPLY"
    rest="${rest#*"$whole"}"
  done

  rest="$line"
  while [[ "$rest" == *.parent* ]] && [[ "$rest" =~ $re_pathlib ]]; do
    local chain="${BASH_REMATCH[3]}" index="${BASH_REMATCH[4]}" tail="${BASH_REMATCH[6]}"
    whole="${BASH_REMATCH[0]}"
    base="${BASH_REMATCH[1]}"
    if [[ -n "$index" ]]; then ups=$((10#$index + 1)); else ups=$((${#chain} / 7)); fi
    # Path(__file__) is the file, one level below the directory the rest resolves against.
    [[ "$base" == Path\(__file__\)* ]] && ups=$((ups - 1))
    up "$ups"
    base="$REPLY"
    literals "$tail"
    consider "$file" "$n" "$base/${REPLY#./}"
    rest="${rest#*"$whole"}"
  done
}

pathspecs=()
for ext in sh bash mjs js cjs jsx ts mts cts tsx py ps1 psm1; do
  pathspecs+=("plugins/*.$ext")
done
while IFS= read -r p; do
  [[ "${p##*/}" != *.* && -f "$p" ]] || continue
  first=""
  IFS= read -r -n 2 first <"$p" || true
  [[ "$first" == '#!' ]] && pathspecs+=(":(literal)$p")
done < <(git ls-files plugins)
grep_rc=0
hits="$(git grep -n -I -E -e '\.\.[/\\]' -e "[\"']\.\.[\"']" -e '\.parent' -- "${pathspecs[@]}")" || grep_rc=$?
if ((grep_rc > 1)); then
  echo "check-plugin-imports: git grep failed (exit $grep_rc)" >&2
  exit 2
fi
while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue
  file="${hit%%:*}"
  hit="${hit#*:}"
  scan_line "$file" "${hit%%:*}" "${hit#*:}"
done <<<"$hits"

errors=0
declare -A listed=()
entries=()
if [[ -f "$exceptions" ]]; then
  # shellcheck disable=SC2310  # the non-zero return IS the handled case; the library reports it
  read_list::into entries "$exceptions" --comments inline || exit 2
fi
for entry in ${entries[@]+"${entries[@]}"}; do
  read -r path sib date reason <<<"$entry"
  if [[ -z "${reason:-}" || ! "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "MALFORMED: $exceptions: '$entry' is not <path> <sibling> <YYYY-MM-DD> <reason>." >&2
    errors=$((errors + 1))
    read_list::mark_used "$entry"
    continue
  fi
  listed["$path $sib"]="$entry"
  [[ -n "${crossing_keys["$path $sib"]:-}" ]] && read_list::mark_used "$entry"
done

for c in ${crossings[@]+"${crossings[@]}"}; do
  IFS=$'\t' read -r file n sib target <<<"$c"
  [[ -n "${listed["$file $sib"]:-}" ]] && continue
  echo "$file:$n: breaks the boundary rule \"$RULE\" (docs/conventions/architecture/README.md): resolves to $target in the $sib plugin. Give the plugin its own copy or fixture, or list the file in $exceptions with the reason." >&2
  errors=$((errors + 1))
done

stale=()
read_list::stale_to stale entries
for entry in ${stale[@]+"${stale[@]}"}; do
  read_list::stale_line "$exceptions" "$entry" 'no longer loads a file from that sibling plugin.'
  errors=$((errors + 1))
done

((errors == 0)) || exit 1
echo "No plugin loads a file from a sibling plugin outside $exceptions."
