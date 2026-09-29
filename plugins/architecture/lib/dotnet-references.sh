#!/usr/bin/env bash
# Shared reader for .NET PackageReference and ProjectReference Include values.
#
# WHY. map-landscape's portfolio collector and map-dependencies both cite the
# same declarations. Two copies of the match would drift, and a second parser
# is how a portfolio row and a graph edge stop describing the same file.
# This is the one reader. It matches the historical one-line
# `<(Package|Project)Reference ... Include="...">` span and nothing else:
# an Include on the following line, a single-quoted Include, and an Update=
# version override are all invisible, on purpose, so the portfolio names do
# not change when the graph starts using the same function.
#
# Sourced, not executed. Executing it exits 2.
#
#   dotnet_reference_records <file>
#     One line per match: kind<TAB>include<TAB>declaration
#     kind is "package" or "project". declaration is the matched tag text.
#   dotnet_reference_includes <file>
#     Include values only, one per line, in file order. This is the
#     portfolio-facts contract.
#
# Portability: bash plus POSIX awk. No jq, no `grep -P`, no python.
# shellcheck shell=bash

# The Include value is the same extended regular expression portfolio-facts.sh
# used inline. awk walks it left to right, non-overlapping, which is what
# `grep -oE` does, including more than one tag on a single line. The
# declaration recorded for evidence continues through the end of that tag
# so a Version attribute on the same tag is part of the citation. The Include
# value itself does not change.
# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_dotnet_reference_awk='
{
  line = $0
  sub(/\r$/, "", line)
  rest = line
  while (match(rest, /<(Package|Project)Reference[^>]*Include="[^"]*"/)) {
    start = RSTART
    decl = substr(rest, RSTART, RLENGTH)
    tail = substr(rest, RSTART + RLENGTH)
    if (match(tail, /^[^>]*>/)) decl = decl substr(tail, 1, RLENGTH)
    kind = "package"
    if (decl ~ /^<ProjectReference/) kind = "project"
    inc = decl
    sub(/^.*Include="/, "", inc)
    sub(/".*$/, "", inc)
    printf "%s\t%s\t%s\n", kind, inc, decl
    rest = substr(rest, start + length(decl))
  }
}
'

dotnet_reference_records() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  awk "$_dotnet_reference_awk" "$file"
}

dotnet_reference_includes() {
  local file="$1"
  dotnet_reference_records "$file" | awk -F '\t' 'NF >= 2 {
    decl = $3
    for (i = 4; i <= NF; i++) decl = decl "\t" $i
    print $2
  }'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'dotnet-references.sh is sourced by collectors; it is not a command.\n' >&2
  exit 2
fi
