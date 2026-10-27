#!/usr/bin/env bash
# dotnet-test-selection.sh <test file>...: the {tests} expansion for dotnet test.
#
# Groups the given C# test files by owning project, the nearest *.csproj walking
# up from each file, and prints one line per project, in first-seen order:
#
#   '<project>' --filter 'FullyQualifiedName~<Namespace>.<Class>.|...'
#
# with one term per top-level class the project's given files declare. The
# namespace comes from a file-scoped declaration or the enclosing namespace
# blocks, joined with `.`; a class in no namespace is its bare name. The
# trailing `.` keeps `~` (contains) from also matching a class whose name
# extends this one. A class holding nested classes also gets a `<Class>+` term,
# so their tests match whether the adapter joins a nested class with `.` or `+`.
# A generic class gets one term with no trailing dot, since this script does not
# know how the adapter spells its type parameters. Comments, string and
# character literals and preprocessor lines are skipped before classes are read.
#
# Each line is shell-quoted, so `dotnet test <line>` runs one project. A project
# path is relative to the working directory when the project sits under it,
# absolute otherwise.
#
# Exit 0: printed. 1: a file is unreadable, has no owning project, has a
# directory with more than one *.csproj nearest it, or declares no top-level
# class; nothing is printed. 2: usage error.
set -uo pipefail
shopt -s nullglob

self=dotnet-test-selection.sh
if (($# == 0)); then
  printf 'usage: %s <test file>...\n' "$self" >&2
  exit 2
fi
cwd="$(pwd -P)" || exit 2

# One `<Namespace>.<Class><TAB><generic><TAB><holds a nested class>` line per
# top-level class, the two flags 1 or 0.
classes_of() {
  awk '
  function top() { return nsn ? nsdepth[nsn] : 0 }
  function punct(c) {
    if (c == ";") {
      if (pend != "") { filens = pend; pend = "" }
    } else if (c == "{") {
      depth++
      if (pend != "") { nsn++; nsname[nsn] = pend; nsdepth[nsn] = depth; pend = "" }
    } else if (c == "}") {
      if (nsn && depth == nsdepth[nsn]) nsn--
      depth--
    }
  }
  function emit(name, generic,   k, full) {
    full = filens
    for (k = 1; k <= nsn; k++) full = (full == "" ? "" : full ".") nsname[k]
    full = (full == "" ? "" : full ".") name
    cur = full
    if (!(full in gen)) { order[++count] = full; gen[full] = generic }
  }
  {
    sub(/\r$/, "")
    line = $0
    if (mode == "" && line ~ /^[ \t]*#/) next
    # Blank out comments and literals, keeping code characters in place.
    clean = ""
    n = length(line)
    i = 1
    while (i <= n) {
      c = substr(line, i, 1)
      if (mode == "block") { if (substr(line, i, 2) == "*/") { mode = ""; i += 2 } else i++; continue }
      if (mode == "raw") { if (substr(line, i, length(rawq)) == rawq) { mode = ""; i += length(rawq) } else i++; continue }
      if (mode == "vstr") {
        if (c != "\"") i++
        else if (substr(line, i + 1, 1) == "\"") i += 2
        else { mode = ""; i++ }
        continue
      }
      if (mode == "str" || mode == "chr") {
        if (c == "\\") i += 2
        else { if (c == (mode == "str" ? "\"" : "\047")) mode = ""; i++ }
        continue
      }
      if (substr(line, i, 2) == "//") break
      if (substr(line, i, 2) == "/*") { mode = "block"; i += 2; clean = clean " "; continue }
      if (c == "\"") {
        p1 = i > 1 ? substr(line, i - 1, 1) : ""
        p2 = i > 2 ? substr(line, i - 2, 1) : ""
        q = 1
        while (substr(line, i + q, 1) == "\"") q++
        clean = clean " "
        if (p1 == "@" || (p1 == "$" && p2 == "@")) { mode = "vstr"; i++ }
        else if (q >= 3) { mode = "raw"; rawq = substr(line, i, q); i += q }
        else { mode = "str"; i++ }
        continue
      }
      if (c == "\047") { mode = "chr"; i++; clean = clean " "; continue }
      clean = clean c
      i++
    }
    if (mode == "str" || mode == "chr") mode = ""
    rest = " " clean
    while (match(rest, /[{};]|[^A-Za-z0-9_@.](namespace|class)[ \t]+@?[A-Za-z_][A-Za-z0-9_.]*/)) {
      tok = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      if (RLENGTH == 1) { punct(tok); continue }
      c = substr(tok, 1, 1)
      if (c == "{" || c == "}" || c == ";") punct(c)
      split(substr(tok, 2), w, /[ \t]+/)
      name = w[2]
      gsub(/@/, "", name)
      if (w[1] == "namespace") pend = name
      else {
        sub(/[^A-Za-z0-9_].*/, "", name)
        # `where T : class where U : ...` is a constraint, not a class named where.
        if (name == "where") continue
        if (depth == top()) emit(name, rest ~ /^[ \t]*</ ? 1 : 0)
        else if (cur != "") nested[cur] = 1
      }
    }
  }
  END {
    for (k = 1; k <= count; k++) print order[k] "\t" gen[order[k]] "\t" (order[k] in nested ? 1 : 0)
  }' <"$1"
}

quote() {
  local s="'" q="'\\''"
  printf "'%s'" "${1//"$s"/$q}"
}

declare -a order=()
declare -A terms=() seen=()
fail=0
for f in "$@"; do
  if [[ ! -f "$f" || ! -r "$f" ]]; then
    printf '%s: cannot read %s\n' "$self" "$f" >&2
    fail=1
    continue
  fi
  if ! dir="$(CDPATH='' cd -- "$(dirname -- "$f")" && pwd -P)"; then
    printf '%s: cannot resolve the directory of %s\n' "$self" "$f" >&2
    fail=1
    continue
  fi
  proj=""
  while :; do
    found=("$dir"/*.csproj)
    if ((${#found[@]} > 1)); then
      printf '%s: %s: more than one project in %s\n' "$self" "$f" "$dir" >&2
      break
    fi
    if ((${#found[@]} == 1)); then
      proj="${found[0]}"
      break
    fi
    if [[ "$dir" == / ]]; then
      printf '%s: %s: no *.csproj in its directory or any above it\n' "$self" "$f" >&2
      break
    fi
    dir="${dir%/*}"
    [[ -n "$dir" ]] || dir=/
  done
  if [[ -z "$proj" ]]; then
    fail=1
    continue
  fi
  if ! classes="$(classes_of "$f")"; then
    printf '%s: cannot parse %s\n' "$self" "$f" >&2
    fail=1
    continue
  fi
  if [[ -z "$classes" ]]; then
    printf '%s: %s declares no top-level class\n' "$self" "$f" >&2
    fail=1
    continue
  fi
  if [[ -z "${terms[$proj]+x}" ]]; then
    order+=("$proj")
    terms["$proj"]=""
  fi
  while IFS=$'\t' read -r name generic nested; do
    want=("FullyQualifiedName~$name")
    if [[ "$generic" != 1 ]]; then
      want=("FullyQualifiedName~$name.")
      [[ "$nested" != 1 ]] || want+=("FullyQualifiedName~$name+")
    fi
    for term in "${want[@]}"; do
      key="$proj"$'\t'"$term"
      [[ -z "${seen[$key]:-}" ]] || continue
      seen["$key"]=1
      terms["$proj"]+="${terms[$proj]:+|}$term"
    done
  done <<<"$classes"
done
((fail)) && exit 1

for proj in "${order[@]}"; do
  shown="$proj"
  [[ "$proj" != "$cwd"/* ]] || shown="${proj#"$cwd"/}"
  printf '%s --filter %s\n' "$(quote "$shown")" "$(quote "${terms[$proj]}")"
done
