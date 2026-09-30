#!/usr/bin/env bash
# Reader for Python manifests: pyproject.toml and requirements*.txt.
#
# WHY. map-dependencies cites a Python project's declared requirements and the
# local projects its path references name. setup.py is executable code, so it
# is never run or parsed here; the collector reports it as unread.
#
# Sourced, not executed. Executing it exits 2.
#
#   py_project_records <pyproject.toml>
#     One line per fact, tab separated:
#       name<TAB>value                              [project] or [tool.poetry] name
#       pkg<TAB>name<TAB>declaration                a named requirement
#       path<TAB>target<TAB>declaration<TAB>name    a requirement that names a
#                                                   local path: "name @ file:...",
#                                                   a poetry or uv entry with path =
#       member<TAB>glob<TAB>declaration             a [tool.uv.workspace] members entry
#       exclude<TAB>glob<TAB>declaration            a [tool.uv.workspace] exclude entry
#       unread<TAB>declaration                      a shape this reader skips
#     Read: [project] dependencies, [project.optional-dependencies] and
#     [dependency-groups] arrays (PEP 508 strings), [tool.poetry.dependencies]
#     and [tool.poetry.group.<g>.dependencies] entries, [tool.uv.sources]
#     entries, [tool.uv.workspace] members and exclude arrays. Names are normalized (lower case, runs of - _ . become -).
#     Unread: dynamic = ["dependencies"], a dependency value that is not a
#     string, an inline table split across lines, a poetry dependency written
#     as its own [table], a uv source with workspace = true or a list of
#     sources, an unterminated array. Lines inside a multi-line string are
#     skipped.
#   py_requirements_records <requirements.txt>
#     pkg, path and unread lines as above, plus:
#       include<TAB>path<TAB>declaration            a -r / --requirement line
#     A -e, ./ or ../ line is a path line with no name. -c and index options
#     give no line; any other option is unread. A line ending in a backslash
#     joins the next one.
#
# Portability: bash plus POSIX awk.
# shellcheck shell=bash

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_py_awk_common='
BEGIN { sq = "\047"; dq = "\"" }
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function tidy(d) { gsub(/\t/, " ", d); return d }
function norm(n) { n = tolower(n); gsub(/[-_.]+/, "-", n); return n }
function unread(d) { printf "unread\t%s\n", tidy(d) }
function pkg(n, d) { printf "pkg\t%s\t%s\n", norm(n), tidy(d) }
function path(p, d, n) { printf "path\t%s\t%s\t%s\n", p, tidy(d), norm(n) }
function pep508(s, decl,    t, name, rest, u) {
  t = s
  sub(/[[:space:]]*;.*$/, "", t)
  t = trim(t)
  if (!match(t, /^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?/)) { unread(decl); return }
  name = substr(t, 1, RLENGTH)
  rest = substr(t, RLENGTH + 1)
  sub(/^[[:space:]]*\[[^]]*\]/, "", rest)
  rest = trim(rest)
  if (rest ~ /^@/) {
    u = trim(substr(rest, 2))
    if (u ~ /^file:/) { sub(/^file:/, "", u); path(u, decl, name) }
    else pkg(name, decl)
  } else if (rest == "" || rest ~ /^([<>=!~(]|===)/) pkg(name, decl)
  else unread(decl)
}
'

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_py_toml_awk="$_py_awk_common"'
function cut_comment(s,    i, c, q, n) {
  q = ""; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\" && q == dq) i++; else if (c == q) q = "" }
    else if (c == dq || c == sq) q = c
    else if (c == "#") return substr(s, 1, i - 1)
  }
  return s
}
function depth(s,    i, c, q, n, d) {
  q = ""; d = 0; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\" && q == dq) i++; else if (c == q) q = "" }
    else if (c == dq || c == sq) q = c
    else if (c == "[" || c == "{") d++
    else if (c == "]" || c == "}") d--
  }
  return d
}
function count(s, d) { return gsub(d, "", s) }
function unquote(v) {
  if (v ~ /^"[^"]*"$/ || v ~ ("^" sq "[^" sq "]*" sq "$")) return substr(v, 2, length(v) - 2)
  return ""
}
function elems(text, mode,    i, c, q, n, start, item) {
  text = trim(text)
  sub(/^\[/, "", text)
  sub(/\]$/, "", text)
  n = length(text)
  i = 1
  while (i <= n) {
    c = substr(text, i, 1)
    if (c ~ /[[:space:],]/) { i++; continue }
    if (c != dq && c != sq) { unread(trim(substr(text, i))); return }
    q = c
    start = i
    for (i++; i <= n; i++) {
      c = substr(text, i, 1)
      if (c == "\\" && q == dq) i++
      else if (c == q) break
    }
    item = substr(text, start, i - start + 1)
    if (mode == "deps") pep508(substr(item, 2, length(item) - 2), item)
    else printf "%s\t%s\t%s\n", mode, substr(item, 2, length(item) - 2), tidy((mode == "member" ? "members" : mode) " " item)
    i++
  }
}
function finish() {
  if (acc_kind == "dyn") {
    if (index(acc, dq "dependencies" dq) || index(acc, sq "dependencies" sq)) unread("dynamic = " acc)
  } else if (acc_kind == "tbl") unread(acc)
  else elems(acc, acc_kind)
  acc = ""
}
function start_array(kind, k, v, s) {
  if (v !~ /^\[/) { if (kind != "dyn") unread(s); return }
  acc_kind = kind
  acc_key = k
  acc = v
  if (depth(acc) <= 0) finish()
}
function named_table(k, v, s, mode,    p) {
  if (mode == "poetry" && k == "python") return
  if (depth(v) > 0) { acc_kind = "tbl"; acc_key = k; acc = s; return }
  if (v ~ /^\{/) {
    if (match(v, "[{,][[:space:]]*path[[:space:]]*=[[:space:]]*(\"[^\"]*\"|" sq "[^" sq "]*" sq ")")) {
      p = substr(v, RSTART, RLENGTH)
      sub(/^[^=]*=[[:space:]]*/, "", p)
      path(substr(p, 2, length(p) - 2), s, k)
    } else if (mode == "uv") {
      if (match(v, "[{,][[:space:]]*workspace[[:space:]]*=")) unread(s)
    } else pkg(k, s)
    return
  }
  if (mode == "uv") { if (v ~ /^\[/) unread(s); return }
  if (unquote(v) != "") pkg(k, s)
  else unread(s)
}
{
  line = $0
  sub(/\r$/, "", line)
  if (inml != "") { if (count(line, inml) % 2 == 1) inml = ""; next }
  s = trim(cut_comment(line))
  if (count(s, dq dq dq) % 2 == 1) inml = dq dq dq
  else if (count(s, sq sq sq) % 2 == 1) inml = sq sq sq
  if (acc != "") {
    acc = acc " " s
    if (depth(acc) <= 0) { gsub(/[[:space:]]+/, " ", acc); finish() }
    next
  }
  if (s == "") next
  if (s ~ /^\[\[/) { sec = "[[]]"; next }
  if (s ~ /^\[/) {
    sec = s
    sub(/^\[[[:space:]]*/, "", sec)
    sub(/[[:space:]]*\].*$/, "", sec)
    gsub(/[[:space:]"]/, "", sec)
    gsub(sq, "", sec)
    if (sec ~ /^tool\.poetry(\.group\.[^.]+)?\.dependencies\.[^.]+$/) unread("[" sec "]")
    next
  }
  if (!match(s, /^("[^"]*"|[A-Za-z0-9_.-]+)[[:space:]]*=/)) next
  k = trim(substr(s, 1, RLENGTH - 1))
  v = trim(substr(s, RLENGTH + 1))
  gsub(/^"|"$/, "", k)
  if (sec == "project") {
    if (k == "name" && unquote(v) != "") print "name\t" unquote(v)
    else if (k == "dependencies") start_array("deps", k, v, s)
    else if (k == "dynamic") start_array("dyn", k, v, s)
    else if (k == "optional-dependencies") unread(s)
  } else if (sec == "tool.poetry") {
    if (k == "name" && unquote(v) != "") print "name\t" unquote(v)
  } else if (sec == "project.optional-dependencies" || sec == "dependency-groups") start_array("deps", k, v, s)
  else if (sec == "tool.uv.workspace" && (k == "members" || k == "exclude")) start_array(k == "members" ? "member" : "exclude", k, v, s)
  else if (sec ~ /^tool\.poetry(\.group\.[^.]+)?\.dependencies$/) named_table(k, v, s, "poetry")
  else if (sec == "tool.uv.sources") named_table(k, v, s, "uv")
}
END { if (acc != "") unread("<unterminated array: " acc_key ">") }
'

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_py_req_awk="$_py_awk_common"'
function pathlike(t) { return t ~ /^(\.\.?(\/|$)|\/)/ }
function local_path(t, decl) {
  sub(/#.*$/, "", t)
  sub(/\[[^]]*\]$/, "", t)
  path(trim(t), decl, "")
}
{
  line = $0
  sub(/\r$/, "", line)
  while (line ~ /\\$/) {
    sub(/\\$/, "", line)
    if ((getline more) > 0) { sub(/\r$/, "", more); line = line more } else break
  }
  sub(/(^|[[:space:]])#.*$/, "", line)
  gsub(/[[:space:]]+--hash=[^[:space:]]+/, "", line)
  line = trim(line)
  if (line == "") next
  if (match(line, /^(-r|--requirement)[[:space:]=]*/)) {
    t = substr(line, RLENGTH + 1)
    if (t == "") unread(line)
    else printf "include\t%s\t%s\n", t, tidy(line)
  } else if (match(line, /^(-e|--editable)[[:space:]=]*/)) {
    t = substr(line, RLENGTH + 1)
    if (t ~ /:\/\//) {
      if (match(t, /#egg=[A-Za-z0-9._-]+/)) pkg(substr(t, RSTART + 5, RLENGTH - 5), line)
      else unread(line)
    } else {
      sub(/^file:/, "", t)
      if (pathlike(t)) local_path(t, line)
      else unread(line)
    }
  } else if (line ~ /^-(i|f|c)([[:space:]=]|$)|^--(index-url|extra-index-url|find-links|trusted-host|no-index|pre|prefer-binary|no-binary|only-binary|require-hashes|use-feature|constraint)([[:space:]=]|$)/) next
  else if (line ~ /^-/) unread(line)
  else if (pathlike(line)) local_path(line, line)
  else pep508(line, line)
}
'

py_project_records() {
  [[ -r "$1" ]] || return 0
  awk "$_py_toml_awk" "$1"
}

py_requirements_records() {
  [[ -r "$1" ]] || return 0
  awk "$_py_req_awk" "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'python-references.sh is sourced by collectors; it is not a command.\n' >&2
  exit 2
fi
