#!/usr/bin/env bash
# Reader for Cargo.toml.
#
# WHY. map-dependencies cites a Rust package's local path dependencies and the
# packages a Cargo workspace names as members, and says so when a manifest
# shape is one it does not read.
#
# Sourced, not executed. Executing it exits 2.
#
#   rust_manifest_records <Cargo.toml>
#     One line per fact, tab separated:
#       name<TAB>value                       [package] name
#       workspace                            the file has a [workspace] table
#       member<TAB>glob<TAB>declaration      a [workspace] members entry
#       exclude<TAB>glob<TAB>declaration     a [workspace] exclude entry
#       path<TAB>target<TAB>declaration<TAB>name
#                                            a dependency with path =
#       pkg<TAB>name<TAB>declaration         any other dependency (a package
#                                            renamed with package = is read as
#                                            its real name; case and _ fold)
#       inherit<TAB>name<TAB>declaration     workspace = true
#       wpath<TAB>target<TAB>declaration<TAB>name
#       wpkg<TAB>name<TAB>real<TAB>declaration
#                                            the same two shapes declared in
#                                            [workspace.dependencies]
#       unread<TAB>declaration               a shape this reader skips
#     Read: [dependencies], [dev-dependencies], [build-dependencies] and
#     [workspace.dependencies], written as name = "1", name = { ... },
#     name.path = "..", or a [dependencies.name] table; [workspace] members and
#     exclude arrays. Unread: any [target.*] dependency table, a path = under
#     [patch] or [replace], a dependency value that is neither a string nor an
#     inline table, an inline table split across lines, a members or exclude
#     value that is not an array. Lines inside a multi-line string are skipped.
#     Resolving inherit against wpath and wpkg is the collector's job.
#
# Portability: bash plus POSIX awk.
# shellcheck shell=bash

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_rust_awk='
BEGIN { sq = "\047"; dq = "\""; tbls = "^(dependencies|dev-dependencies|build-dependencies|workspace\\.dependencies)" }
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function tidy(d) { gsub(/\t/, " ", d); return d }
function unread(d) { printf "unread\t%s\n", tidy(d) }
function count(s, d) { return gsub(d, "", s) }
function norm(n) { n = tolower(n); gsub(/_/, "-", n); return n }
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
    printf "%s\t%s\t%s\n", mode, substr(item, 2, length(item) - 2), tidy((mode == "member" ? "members" : mode) " " item)
    i++
  }
}
function finish() {
  if (acc_kind == "tbl") unread(acc)
  else elems(acc, acc_kind)
  acc = ""
}
function start_array(kind, v, s) {
  if (v !~ /^\[/) { unread(s); return }
  acc_kind = kind
  acc = v
  if (depth(acc) <= 0) finish()
}
function touch(key, dep, decl, ws) {
  if (key in seen) return
  seen[key] = 1
  order[++nord] = key
  d_dep[key] = dep
  d_decl[key] = decl
  d_ws[key] = ws
  d_pkg[key] = dep
}
function setattr(key, dep, attr, val, decl, ws,    p) {
  touch(key, dep, decl, ws)
  if (attr == "path") {
    p = unquote(val)
    if (p != "") { d_path[key] = p; d_pdecl[key] = decl } else unread(decl)
  } else if (attr == "workspace") {
    if (val == "true") { d_inherits[key] = 1; d_idecl[key] = decl }
  } else if (attr == "package") {
    p = unquote(val)
    if (p != "") d_pkg[key] = p
  }
}
function inline_value(v, name,    p) {
  if (!match(v, "[{,][[:space:]]*" name "[[:space:]]*=[[:space:]]*(\"[^\"]*\"|" sq "[^" sq "]*" sq "|true)")) return ""
  p = substr(v, RSTART, RLENGTH)
  sub(/^[^=]*=[[:space:]]*/, "", p)
  return p
}
function entry(base, dep, v, s, ws,    key, p) {
  key = base SUBSEP dep
  if (v ~ /^\{/) {
    if (depth(v) > 0) { acc_kind = "tbl"; acc = s; return }
    touch(key, dep, s, ws)
    if ((p = inline_value(v, "path")) != "") setattr(key, dep, "path", p, s, ws)
    if ((p = inline_value(v, "workspace")) != "") setattr(key, dep, "workspace", p, s, ws)
    if ((p = inline_value(v, "package")) != "") setattr(key, dep, "package", p, s, ws)
  } else if (unquote(v) != "") touch(key, dep, s, ws)
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
  if (s ~ /^\[\[/) { mode = ""; next }
  if (s ~ /^\[/) {
    hdr = s
    sec = s
    sub(/^\[[[:space:]]*/, "", sec)
    sub(/[[:space:]]*\].*$/, "", sec)
    gsub(/[[:space:]"]/, "", sec)
    gsub(sq, "", sec)
    mode = ""
    if ((sec == "workspace" || sec ~ /^workspace\./) && !wsseen) { wsseen = 1; print "workspace" }
    if (sec ~ /^target\..*dependencies(\.[^.]+)?$/) unread(hdr)
    else if (sec ~ (tbls "$")) { mode = "tbl"; base = sec }
    else if (match(sec, tbls "\\.")) { mode = "sub"; base = substr(sec, 1, RLENGTH - 1); subdep = substr(sec, RLENGTH + 1); subhdr = hdr }
    else if (sec ~ /^(patch\.|replace$)/) mode = "patch"
    else if (sec == "package" || sec == "workspace") mode = sec
    next
  }
  if (mode == "patch") { if (s ~ /(^|[{,[:space:]])path[[:space:]]*=/) unread(s); next }
  if (!match(s, /^("[^"]*"|[A-Za-z0-9_.-]+)[[:space:]]*=/)) next
  k = trim(substr(s, 1, RLENGTH - 1))
  v = trim(substr(s, RLENGTH + 1))
  gsub(/^"|"$/, "", k)
  if (mode == "package") { if (k == "name" && unquote(v) != "") print "name\t" unquote(v) }
  else if (mode == "workspace") {
    if (k == "members") start_array("member", v, s)
    else if (k == "exclude") start_array("exclude", v, s)
  } else if (mode == "tbl") {
    ws = (base ~ /^workspace/)
    if (k ~ /\./) {
      dep = substr(k, 1, index(k, ".") - 1)
      setattr(base SUBSEP dep, dep, substr(k, index(k, ".") + 1), v, s, ws)
    } else entry(base, k, v, s, ws)
  } else if (mode == "sub") setattr(base SUBSEP subdep, subdep, k, v, subhdr " " s, base ~ /^workspace/)
}
END {
  if (acc != "") unread("<unterminated array>")
  for (i = 1; i <= nord; i++) {
    key = order[i]
    if (d_path[key] != "") printf "%s\t%s\t%s\t%s\n", d_ws[key] ? "wpath" : "path", d_path[key], tidy(d_pdecl[key]), d_dep[key]
    else if (d_inherits[key] && !d_ws[key]) printf "inherit\t%s\t%s\n", d_dep[key], tidy(d_idecl[key])
    else if (d_ws[key]) printf "wpkg\t%s\t%s\t%s\n", d_dep[key], norm(d_pkg[key]), tidy(d_decl[key])
    else printf "pkg\t%s\t%s\n", norm(d_pkg[key]), tidy(d_decl[key])
  }
}
'

rust_manifest_records() {
  [[ -r "$1" ]] || return 0
  awk "$_rust_awk" "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'rust-references.sh is sourced by collectors; it is not a command.\n' >&2
  exit 2
fi
