#!/usr/bin/env bash
# Reader for Node workspace manifests: package.json and pnpm-workspace.yaml.
#
# WHY. map-dependencies cites a Node package's declared dependencies and the
# workspace members they name. A JSON manifest is not line-oriented, so the
# reader walks the whole file as tokens with a container stack and takes
# members by position. A nested object that reuses a section name, such as
# pnpm.overrides.dependencies, is never read as the section.
#
# Sourced, not executed. Executing it exits 2.
#
#   node_manifest_records <package.json>
#     One line per fact, tab separated:
#       name<TAB>value                              the "name" member
#       workspace<TAB>glob<TAB>declaration          one "workspaces" glob
#       dep<TAB>section<TAB>name<TAB>spec<TAB>declaration
#                                                   one entry of dependencies,
#                                                   devDependencies,
#                                                   peerDependencies or
#                                                   optionalDependencies
#       unread<TAB>declaration                      a shape this reader skips
#     The workspaces member is an array of strings, or an object whose
#     "packages" member is one. declaration is the member as written,
#     "name": "spec". An unterminated file gives one unread line.
#   node_pnpm_workspace_records <pnpm-workspace.yaml>
#     The same workspace and unread lines for the block list under the
#     top-level "packages:" key. A flow list (packages: [a, b]) is unread.
#   node_glob_regex <glob>
#     An anchored ERE that matches a workspace-relative folder path. * stays
#     inside one path segment, ** crosses segments, ? is one character. Fails
#     for a negated glob or any glob using syntax beyond those characters.
#
# Portability: bash plus POSIX awk. No jq, no `grep -P`, no python.
# shellcheck shell=bash

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_node_manifest_awk='
function unread(decl) { printf "unread\t%s\n", decl }
function shown(kind, tok) { return kind == "obj" ? "{...}" : kind == "arr" ? "[...]" : tok }
function skipped(kind) { return (kind == "obj" || kind == "arr") ? "skip" : "" }
function glob(kind, tok) {
  if (kind == "str") printf "workspace\t%s\t%s\n", substr(tok, 2, length(tok) - 2), tok
  else unread(shown(kind, tok))
  return skipped(kind)
}
# What to do with the value that starts here: "push" descends into a container
# this reader reads, "skip" passes over one it does not, "" is a scalar.
function handle(kind, tok,    k1, k2) {
  if (d == 0) {
    if (kind == "obj") return "push"
    unread(shown(kind, tok))
    return skipped(kind)
  }
  k1 = key[1]
  if (d == 1) {
    if (k1 == "name" && kind == "str") { print "name\t" substr(tok, 2, length(tok) - 2); return "" }
    if (k1 == "workspaces") {
      if (kind == "obj" || kind == "arr") return "push"
      unread("\"workspaces\": " tok)
      return ""
    }
    if (k1 in sections) {
      if (kind == "obj") return "push"
      unread("\"" k1 "\": " shown(kind, tok))
    }
    return skipped(kind)
  }
  if (k1 == "workspaces") {
    if (d == 2 && typ[2] == "o") return (key[2] == "packages" && kind == "arr") ? "push" : skipped(kind)
    return glob(kind, tok)
  }
  if (d == 2) {
    k2 = key[2]
    if (kind == "str") {
      spec = substr(tok, 2, length(tok) - 2)
      printf "dep\t%s\t%s\t%s\t\"%s\": %s\n", k1, k2, spec, k2, tok
    } else unread("\"" k2 "\": " shown(kind, tok))
  }
  return skipped(kind)
}
{
  line = $0
  sub(/\r$/, "", line)
  buf = buf line "\n"
}
END {
  split("dependencies devDependencies peerDependencies optionalDependencies", names, " ")
  for (i in names) sections[names[i]] = 1
  rest = buf
  d = 0
  skipn = 0
  while (match(rest, /^[[:space:]]*("([^"\\]|\\.)*"|[][{}:,]|[^][[:space:]{}:,"]+)/)) {
    tok = substr(rest, 1, RLENGTH)
    rest = substr(rest, RLENGTH + 1)
    sub(/^[[:space:]]+/, "", tok)
    c = substr(tok, 1, 1)
    if (skipn > 0) {
      if (c == "{" || c == "[") skipn++
      else if (c == "}" || c == "]") { skipn--; if (skipn == 0) st[d] = 3 }
      continue
    }
    if (c == "}" || c == "]") { if (d > 0) d--; st[d] = 3; continue }
    if (c == ",") { st[d] = (typ[d] == "o") ? 0 : 2; continue }
    if (c == ":") { st[d] = 2; continue }
    if (c == "\"" && typ[d] == "o" && st[d] == 0) { key[d] = substr(tok, 2, length(tok) - 2); st[d] = 1; continue }
    kind = (c == "{") ? "obj" : (c == "[") ? "arr" : (c == "\"") ? "str" : "lit"
    act = handle(kind, tok)
    if (act == "push") {
      d++
      typ[d] = (c == "{") ? "o" : "a"
      st[d] = (c == "{") ? 0 : 2
    } else if (act == "skip") skipn = 1
    else st[d] = 3
  }
  if (d != 0 || skipn != 0 || rest !~ /^[[:space:]]*$/) unread("<incomplete or malformed JSON>")
}
'

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_node_pnpm_awk='
function unread(decl) { printf "unread\t%s\n", decl }
BEGIN { sq = "\047"; q = "\"" }
{ line = $0; sub(/\r$/, "", line) }
line ~ /^packages[[:space:]]*:/ {
  value = line
  sub(/^packages[[:space:]]*:[[:space:]]*/, "", value)
  sub(/[[:space:]]+#.*$/, "", value)
  if (value == "" || value ~ /^#/) inlist = 1
  else { inlist = 0; unread(line) }
  next
}
line ~ /^[^[:space:]#-]/ { inlist = 0; next }
inlist && line ~ /^[[:space:]]*-[[:space:]]+/ {
  item = line
  sub(/^[[:space:]]*-[[:space:]]+/, "", item)
  sub(/[[:space:]]+#.*$/, "", item)
  sub(/[[:space:]]+$/, "", item)
  g = item
  first = substr(g, 1, 1)
  if ((first == q || first == sq) && length(g) > 1 && substr(g, length(g), 1) == first) g = substr(g, 2, length(g) - 2)
  printf "workspace\t%s\t- %s\n", g, item
}
'

node_manifest_records() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  awk "$_node_manifest_awk" "$file"
}

node_pnpm_workspace_records() {
  local file="$1"
  [[ -r "$file" ]] || return 0
  awk "$_node_pnpm_awk" "$file"
}

node_glob_regex() {
  awk -v g="$1" '
    BEGIN {
      sub(/^\.\//, "", g)
      sub(/\/+$/, "", g)
      if (g == "" || g ~ /[^A-Za-z0-9_.@\/*?-]/ || g ~ /^\//) exit 1
      out = "^"
      n = length(g)
      i = 1
      while (i <= n) {
        c = substr(g, i, 1)
        if (c == "*" && substr(g, i, 2) == "**") {
          if (substr(g, i + 2, 1) == "/") { out = out "(.*/)?"; i += 3 } else { out = out ".*"; i += 2 }
        } else if (c == "*") { out = out "[^/]*"; i++ }
        else if (c == "?") { out = out "[^/]"; i++ }
        else if (c == ".") { out = out "\\."; i++ }
        else { out = out c; i++ }
      }
      print out "$"
    }
  '
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'node-references.sh is sourced by collectors; it is not a command.\n' >&2
  exit 2
fi
