#!/usr/bin/env bash
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
