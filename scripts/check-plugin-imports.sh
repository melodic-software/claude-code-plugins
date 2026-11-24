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
# A shell variable assigned from this file's location, alone or plus a path, or from
# another such variable holds the directory that names; otherwise one named
# *PLUGIN_ROOT or *PLUGIN_DIR holds the plugin's root, and any other the file's
# directory. One assignment the check cannot resolve leaves a variable untraced.
# Comment lines and path strings with no anchor are not crossings. Accepted limits:
# https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/architecture/README.md#boundary-rules
#
# scripts/plugin-imports-exceptions.txt lists accepted crossings, one line per
# file and sibling plugin: `<path> <sibling> <YYYY-MM-DD> <reason>`. A crossing it
# does not list fails, and so does a listed one that no longer crosses.
#
# Exit codes and streams follow the check-script contract in scripts/README.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

up() {
  local i
  REPLY=.
  for ((i = 0; i < $1; i++)); do REPLY+=/..; done
}

path_chars='[^][:space:]"'"'"'`;)|&<>,}$]*'
re_anchor='(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\$\{[A-Za-z_][A-Za-z0-9_]*%/\*\}|\$\(dirname[^)]*\)|__dirname|import\.meta\.dirname)(/'"$path_chars"')'
re_spec='(from|require\(|import\(|import)[[:space:]]*["'"'"'`](\.\.?/[^"'"'"'`]*)["'"'"'`]'
# shellcheck disable=SC2016  # regex text: the `$` is matched, never expanded
re_join='(join|resolve|Join-Path)[[:space:]]*\(?[[:space:]]*(-Path[[:space:]]+)?[$A-Za-z_][$A-Za-z0-9_.]*(([[:space:]]*,?[[:space:]]*(-ChildPath[[:space:]]+)?["'"'"'][^"'"'"']*["'"'"'])+)'
re_lit='["'"'"']([^"'"'"']*)["'"'"']'
re_pathlib='(Path\(__file__\)(\.resolve\(\))?|[A-Za-z_][A-Za-z0-9_]*)(\.parents\[([0-9]+)\]|(\.parent)+)(([[:space:]]*/[[:space:]]*["'"'"'][^"'"'"']+["'"'"'])+)'

declare -a crossings=()
declare -A crossing_keys=()

declare -A assigned=() traced=() deps=() verify_files=() verify_names=()
declare -a pending=()
verified=""
re_assign='^[[:space:]]*(local[[:space:]]+|readonly[[:space:]]+|declare[[:space:]]+(-[A-Za-z]+[[:space:]]+)?)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
re_cd='\$\(cd([[:space:]]+-[-A-Za-z]*)*[[:space:]]+"?'
re_self='^"?('"$re_cd"')?\$\(dirname([[:space:]]+--)?[[:space:]]+"?\$\{?(0|BASH_SOURCE(\[0\])?)\}?"?\)(/'"$path_chars"')?"?([[:space:]]*&&[[:space:]]*pwd[^)]*\))?"?$|^"?\$\{BASH_SOURCE(\[0\])?%/\*\}"?$'
re_rhs='^"?('"$re_cd"')?\$\{?([A-Za-z_][A-Za-z0-9_]*)(%/\*)?\}?(/'"$path_chars"')?"?([[:space:]]*&&[[:space:]]*pwd[^)]*\))?"?$'

trace() {
  local name="${2%%=*}"
  name="${name##*[[:space:]]}"
  assigned["$1 $name"]+="${2#*=}"$'\n'
}

value_of() {
  local file="$1" rhs="$2" up rel
  REPLY="?" DEPS=""
  if [[ "$rhs" =~ $re_self ]]; then
    norm "${file%/*}" "${BASH_REMATCH[6]:-.}"
    REPLY="${REPLY:-.}"
  elif [[ "$rhs" =~ $re_rhs ]] && [[ -z "${BASH_REMATCH[1]}" || -n "${BASH_REMATCH[6]}" ]]; then
    up="${BASH_REMATCH[4]:+/..}" rel="${BASH_REMATCH[5]}"
    if base_of "$file" "${BASH_REMATCH[3]}"; then
      norm "$REPLY$up" "${rel:-.}"
      REPLY="${REPLY:-.}"
    else
      REPLY="?"
    fi
  fi
}

base_of() {
  local key="$1 $2" t own rhs rem v="" d=""
  if [[ -z "${traced[$key]+x}" && -n "${assigned[$key]+x}" ]]; then
    traced[$key]="?"
    rem="${assigned[$key]%$'\n'}"
    while [[ -n "$rem" ]]; do
      rhs="${rem%%$'\n'*}"
      value_of "$1" "$rhs"
      d+="$DEPS"
      if [[ -n "$v" && "$v" != "$REPLY" ]]; then
        v="?"
        break
      fi
      v="$REPLY"
      [[ "$rhs" != "$rem" ]] || break
      rem="${rem#*$'\n'}"
    done
    traced[$key]="$v"
    deps[$key]="$2"$'\n'"$d"
  fi
  t="${traced[$key]:-?}"
  DEPS=""
  if [[ "$t" != "?" ]]; then
    REPLY="$t"
    DEPS="${deps[$key]}"
  elif [[ "$2" == *PLUGIN_ROOT || "$2" == *PLUGIN_DIR ]]; then
    own="${1#plugins/}"
    REPLY="plugins/${own%%/*}"
  else
    return 1
  fi
}

anchor() {
  local d rem
  if ! base_of "$1" "$4"; then
    consider "$1" "$2" "$3"
  elif [[ -z "$DEPS" || -n "$verified" || "$REPLY" == "${1%/*}" ]]; then
    consider "$1" "$2" "$3" "$REPLY"
  else
    pending+=("$1	$2	$3	$4")
    verify_files["$1"]=1
    rem="$DEPS"
    while [[ -n "$rem" ]]; do
      d="${rem%%$'\n'*}"
      [[ -n "$d" ]] && verify_names["$d"]=1
      [[ "$d" != "$rem" ]] || break
      rem="${rem#*$'\n'}"
    done
  fi
}

declare -A plugin_dirs=()
for _pd in plugins/*/; do
  [[ -d "$_pd" ]] || continue
  _pd="${_pd#plugins/}"
  plugin_dirs["${_pd%/}"]=1
done

consider() {
  local file="$1" n="$2" rel="$3" own sib
  [[ "$rel" == *..* || $# -gt 3 ]] || return 0
  own="${file#plugins/}"
  own="${own%%/*}"
  norm "${4:-${file%/*}}" "$rel"
  [[ "$REPLY" == plugins/?* ]] || return 0
  sib="${REPLY#plugins/}"
  sib="${sib%%/*}"
  [[ "$sib" != "$own" && -n "${plugin_dirs[$sib]:-}" ]] || return 0
  crossings+=("$file	$n	$sib	$REPLY")
  crossing_keys["$file $sib"]=1
}

literals() {
  local text="$1"
  REPLY=.
  while [[ "$text" =~ $re_lit ]]; do
    REPLY+="/${BASH_REMATCH[1]}"
    text="${text#*"${BASH_REMATCH[0]}"}"
  done
}

scan_line() {
  local file="$1" n="$2" line="$3" ext="${1##*.}" s rest base ups whole rel name
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

  rest="$line"
  while [[ "$rest" == */* && ("$rest" == *'$'* || "$rest" == *__dirname* || "$rest" == *import.meta.dirname*) ]] && [[ "$rest" =~ $re_anchor ]]; do
    whole="${BASH_REMATCH[0]}" rel="${BASH_REMATCH[2]}" name="${BASH_REMATCH[1]#\$}"
    name="${name#\{}"
    anchor "$file" "$n" "$rel" "${name%\}}"
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
declare -A shebang=()
while IFS= read -r p; do
  [[ -f "$p" ]] || continue
  first=""
  IFS= read -r -n 2 first <"$p" || true
  [[ "$first" == '#!' ]] && pathspecs+=(":(literal)$p") && shebang["$p"]=1
done < <(git ls-files plugins | LC_ALL=C awk -F/ '$NF !~ /\./')

spec_budget="${CHECK_PLUGIN_IMPORTS_SPEC_BYTES:-16000}"
grep_batch() {
  local rc=0 chunk
  chunk="$(git grep -n -I -E "${patterns[@]}" -- "${batch[@]}")" || rc=$?
  if ((rc > 1)); then
    echo "check-plugin-imports: git grep failed (exit $rc)" >&2
    exit 2
  fi
  [[ -n "$chunk" ]] && hits+="${hits:+$'\n'}$chunk"
  batch=()
  size=0
  batches=$((batches + 1))
}
grep_hits() {
  patterns=() batch=() size=0 batches=0 hits=""
  while [[ "$1" != -- ]]; do
    patterns+=("$1")
    shift
  done
  shift
  local spec
  for spec in "$@"; do
    ((${#batch[@]} && size + ${#spec} + 1 > spec_budget)) && grep_batch
    batch+=("$spec")
    size=$((size + ${#spec} + 1))
  done
  ((${#batch[@]})) && grep_batch
  ((batches > 1)) && hits="$(LC_ALL=C sort -s -t: -k1,1 <<<"$hits")"
  return 0
}
grep_hits -e '\.\.[/\\]' -e "[\"']\.\.[\"']" -e '\.parent' -e '[/]plugins/' -- "${pathspecs[@]}"
uses="$(LC_ALL=C awk '
  {
    p1 = index($0, ":")
    if (!p1) next
    file = substr($0, 1, p1 - 1)
    rest = substr($0, p1 + 1)
    p2 = index(rest, ":")
    if (!p2) next
    line = substr(rest, p2 + 1)
    s = line
    sub(/^[ \t]+/, "", s)
    n = split(file, parts, ".")
    ext = (n > 1) ? parts[n] : ""
    if (ext == "mjs" || ext == "js" || ext == "cjs" || ext == "jsx" || ext == "ts" || ext == "mts" || ext == "cts" || ext == "tsx") {
      if (substr(s, 1, 2) == "//" || substr(s, 1, 1) == "*" || substr(s, 1, 2) == "/*") next
    } else if (ext == "ps1" || ext == "psm1") {
      if (substr(s, 1, 1) == "#" || substr(s, 1, 2) == "<#") next
    } else {
      if (substr(s, 1, 1) == "#") next
    }
    if (index(line, "$") || index(line, "__dirname") || index(line, "import.meta.dirname") ||
        index(line, "from") || index(line, "require") || index(line, "import") ||
        index(line, "join") || index(line, "resolve") || index(line, "Join-Path") ||
        index(line, ".parent")) print
  }
' <<<"$hits")"
declare -A use_files=()
while IFS= read -r hit; do
  file="${hit%%:*}"
  [[ "$hit" == *'$'* && -z "${use_files[$file]:-}" ]] || continue
  [[ "$file" == *.sh || "$file" == *.bash || -n "${shebang[$file]:-}" ]] && use_files["$file"]=1
done <<<"$uses"
if ((${#use_files[@]})); then
  shellspecs=()
  for p in "${!use_files[@]}"; do shellspecs+=(":(literal)$p"); done
  grep_hits -e "${re_assign%'(.*)$'}"'"?\$.*([/%]|dirname)' -- "${shellspecs[@]}"
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    file="${hit%%:*}"
    hit="${hit#*:}"
    trace "$file" "${hit#*:}"
  done <<<"$hits"
fi
while IFS= read -r hit; do
  [[ -n "$hit" ]] || continue
  file="${hit%%:*}"
  hit="${hit#*:}"
  scan_line "$file" "${hit%%:*}" "${hit#*:}"
done <<<"$uses"

if ((${#pending[@]})); then
  shellspecs=()
  for p in "${!verify_files[@]}"; do shellspecs+=(":(literal)$p"); done
  alt="${!verify_names[*]}"
  grep_hits -e "${re_assign%%'([A-Za-z_]'*}(${alt// /|})=" -- "${shellspecs[@]}"
  for key in "${!assigned[@]}"; do
    [[ -n "${verify_files[${key% *}]:-}" && -n "${verify_names[${key##* }]:-}" ]] && unset 'assigned[$key]'
  done
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    file="${hit%%:*}"
    hit="${hit#*:}"
    trace "$file" "${hit#*:}"
  done <<<"$hits"
  traced=() deps=() verified=1
  for p in "${pending[@]}"; do
    IFS=$'\t' read -r file n rel name <<<"$p"
    anchor "$file" "$n" "$rel" "$name"
  done
fi

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
