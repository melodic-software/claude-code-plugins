#!/usr/bin/env bash
# Shared reader for .NET PackageReference and ProjectReference Include values.
#
# WHY. map-landscape's portfolio collector and map-dependencies both cite the
# same declarations. Two copies of the match would drift, and a second parser
# is how a portfolio row and a graph edge stop describing the same file.
# This is the one reader.
#
# The reader takes the whole file as one string. It drops XML comments (one line
# or many), finds each start tag whose element name ends in "Reference", and
# reads that tag's attributes, so an Include on a later line, a single-quoted
# Include, and a tag that spans lines are all read. A reference inside a comment
# is not an edge. A tag with Update= or Remove= and no Include= modifies another
# declaration and is not a reference. A reference-like tag the reader cannot turn
# into a record is counted, so a caller can say it was skipped.
#
# Sourced, not executed. Executing it exits 2.
#
#   dotnet_reference_records <file>
#     One line per reference: kind<TAB>include<TAB>declaration
#     kind is "package" or "project". declaration is the start tag text with
#     line breaks collapsed to one space.
#   dotnet_reference_includes <file>
#     Include values only, one per line, in file order. This is the
#     portfolio-facts contract.
#   dotnet_reference_unmatched_count <file>
#     How many start tags whose element name ends in "Reference" yielded no
#     record and are not Update= or Remove= modifiers. FrameworkReference,
#     GlobalPackageReference, an empty Include, and a tag with no Include are
#     counted. 0 for a file that cannot be read.
#
#   dotnet_project_property <file> <name>
#     The text of the first <name>...</name> element in the file (comments
#     dropped, whitespace trimmed), or nothing. A value that holds an MSBuild
#     expression, $(...), is not a value this reader can evaluate and prints
#     nothing.
#   dotnet_is_test_project <file>
#     Succeeds when the file sets IsTestProject to true, or has a
#     PackageReference whose Include is Microsoft.NET.Test.Sdk, xunit*,
#     NUnit*, MSTest*, or Microsoft.Testing.Platform*, matched
#     case-insensitively as NuGet ids are.
#
# Portability: bash plus POSIX awk. No jq, no `grep -P`, no python.
# shellcheck shell=bash

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_dotnet_reference_awk='
function strip_comments(s,    out, i, j) {
  out = ""
  while ((i = index(s, "<!--")) > 0) {
    out = out substr(s, 1, i - 1) " "
    s = substr(s, i + 4)
    j = index(s, "-->")
    if (j == 0) return out
    s = substr(s, j + 3)
  }
  return out s
}
{
  line = $0
  sub(/\r$/, "", line)
  buf = buf line "\n"
}
END {
  sq = "\047"
  q = "\""
  name_re = "<[A-Za-z_][A-Za-z0-9_.:-]*Reference"
  open_re = name_re "[[:space:]/>]"
  tag_re = "^" name_re "([[:space:]]([^>" q sq "]|" q "[^" q "]*" q "|" sq "[^" sq "]*" sq ")*)?/?>"
  attr_re = "^[[:space:]/]*[^[:space:]=/>" q sq "]+[[:space:]]*=[[:space:]]*(" q "[^" q "]*" q "|" sq "[^" sq "]*" sq ")"
  rest = strip_comments(buf)
  if (mode == "prop") {
    if (match(rest, "<" prop "[[:space:]]*>[^<]*</" prop "[[:space:]]*>")) {
      v = substr(rest, RSTART, RLENGTH)
      sub(/^<[^>]*>/, "", v)
      sub(/<.*$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (index(v, "$(") == 0) print v
    }
    exit
  }
  unmatched = 0
  while (match(rest, open_re)) {
    rest = substr(rest, RSTART)
    if (!match(rest, tag_re)) {
      unmatched++
      rest = substr(rest, 2)
      continue
    }
    tag = substr(rest, 1, RLENGTH)
    rest = substr(rest, RLENGTH + 1)
    tname = tag
    sub(/^</, "", tname)
    sub(/[[:space:]\/>].*$/, "", tname)
    body = substr(tag, length(tname) + 2)
    inc = ""; has_inc = 0; modifier = 0
    while (match(body, attr_re)) {
      attr = substr(body, 1, RLENGTH)
      body = substr(body, RLENGTH + 1)
      aname = attr
      sub(/^[[:space:]\/]*/, "", aname)
      sub(/[[:space:]]*=.*$/, "", aname)
      aval = attr
      sub(/^[^=]*=[[:space:]]*/, "", aval)
      aval = substr(aval, 2, length(aval) - 2)
      if (aname == "Include") { inc = aval; has_inc = 1 }
      else if (aname == "Update" || aname == "Remove") modifier = 1
    }
    if (has_inc && inc != "" && (tname == "PackageReference" || tname == "ProjectReference")) {
      if (mode == "records") {
        decl = tag
        gsub(/[[:space:]]*\n[[:space:]]*/, " ", decl)
        printf "%s\t%s\t%s\n", (tname == "ProjectReference" ? "project" : "package"), inc, decl
      }
    } else if (!(modifier && !has_inc)) unmatched++
  }
  if (mode == "count") print unmatched
}
'

dotnet_reference_records() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  awk -v mode=records "$_dotnet_reference_awk" "$file"
}

dotnet_reference_includes() {
  dotnet_reference_records "$1" | awk -F '\t' 'NF >= 2 { print $2 }'
}

dotnet_reference_unmatched_count() {
  local file="$1"
  [[ -r "$file" ]] || {
    printf '0\n'
    return 0
  }
  awk -v mode=count "$_dotnet_reference_awk" "$file"
}

dotnet_project_property() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  awk -v mode=prop -v prop="$2" "$_dotnet_reference_awk" "$file"
}

dotnet_is_test_project() {
  local file="$1" flag
  flag="$(dotnet_project_property "$file" IsTestProject)"
  [[ "${flag,,}" == "true" ]] && return 0
  dotnet_reference_records "$file" | awk -F '\t' '
    $1 == "package" {
      id = tolower($2)
      if (id == "microsoft.net.test.sdk" || id ~ /^(xunit|nunit|mstest|microsoft\.testing\.platform)/) found = 1
    }
    END { exit !found }
  '
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'dotnet-references.sh is sourced by collectors; it is not a command.\n' >&2
  exit 2
fi
