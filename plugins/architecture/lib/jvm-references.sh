#!/usr/bin/env bash
# Reader for JVM build manifests: settings.gradle(.kts), build.gradle(.kts)
# and pom.xml.
#
# WHY. map-dependencies cites which Gradle subprojects a build includes, which
# subprojects another one depends on, and which Maven modules a pom aggregates,
# and says so when a declaration is a shape it does not read.
#
# Sourced, not executed. Executing it exits 2.
#
#   jvm_settings_records <settings.gradle | settings.gradle.kts>
#     include<TAB>project path<TAB>declaration   a literal include argument
#     unread<TAB>declaration                     a shape this reader skips
#   jvm_build_records <build.gradle | build.gradle.kts>
#     project<TAB>project path<TAB>declaration   project(':x') or
#                                                project(path = ':x')
#     unread<TAB>declaration
#   jvm_pom_records <pom.xml>
#     name<TAB>artifactId                        the project's own artifactId
#     module<TAB>path<TAB>declaration            a <modules><module> entry
#     unread<TAB>declaration
#     declaration is the statement as written, comment removed. An include
#     statement spread over several lines is one declaration.
#     Unread in settings: includeFlat, includeBuild, an include with an
#     argument that is not a string literal (a variable, an interpolated
#     string, a spread, a loop body), a statement inside .each, .forEach, for
#     or while, a project(...).projectDir, .buildFileName or .name assignment,
#     and apply from. Unread in a build file: projects.x type-safe accessors,
#     project(...) with a non-literal argument or used as a receiver, and a
#     project( whose arguments leave the line. Unread in a pom: a module value
#     that is empty or holds a ${property}.
#     Version catalog accessors (libs.x) name external coordinates, and this
#     reader draws no external edge for JVM, so it does not read them.
#
# Portability: bash plus POSIX awk.
# shellcheck shell=bash

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_jvm_gradle_awk='
BEGIN { sq = "\047"; dq = "\"" }
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function tidy(d) { gsub(/\t/, " ", d); gsub(/[[:space:]]+/, " ", d); return d }
function unread(d) { printf "unread\t%s\n", tidy(d) }
function strip(line,    i, c, q, n, out) {
  out = ""; q = ""; n = length(line); i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (blk) { if (c == "*" && substr(line, i + 1, 1) == "/") { blk = 0; i += 2 } else i++; continue }
    if (q != "") {
      out = out c
      if (c == "\\") { out = out substr(line, i + 1, 1); i += 2; continue }
      if (c == q) q = ""
      i++
      continue
    }
    if (c == dq || c == sq) { q = c; out = out c; i++; continue }
    if (c == "/" && substr(line, i + 1, 1) == "/") break
    if (c == "/" && substr(line, i + 1, 1) == "*") { blk = 1; out = out " "; i += 2; continue }
    out = out c; i++
  }
  return out
}
function depth(s,    i, c, q, n, d) {
  q = ""; d = 0; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\") i++; else if (c == q) q = "" }
    else if (c == dq || c == sq) q = c
    else if (c == "(") d++
    else if (c == ")") d--
  }
  return d
}
function lits(text,    i, c, q, n, start, item) {
  nl = 0; bad = 0; n = length(text); i = 1
  while (i <= n) {
    c = substr(text, i, 1)
    if (c ~ /[[:space:],()]/) { i++; continue }
    if (c != dq && c != sq) { bad = 1; i++; continue }
    q = c; start = i
    for (i++; i <= n; i++) {
      c = substr(text, i, 1)
      if (c == "\\") i++
      else if (c == q) break
    }
    item = substr(text, start + 1, i - start - 1)
    if (q == dq && item ~ /\$/) bad = 1
    else lit[++nl] = item
    i++
  }
}
function finish(    t, d, i) {
  t = acc
  sub(/^include[[:space:]]*/, "", t)
  lits(t)
  d = tidy(acc)
  for (i = 1; i <= nl; i++) printf "include\t%s\t%s\n", lit[i], d
  if (bad || nl == 0) unread(d)
  acc = ""
}
function complete() { return accparen ? depth(acc) <= 0 : last !~ /,$/ }
function settings_line(s,    rest) {
  if (s ~ /(\.each|\.eachDir|\.forEach|\.collect|\.findAll)([[:space:](]|$)/ || s ~ /^(for|while)[[:space:]]*\(/) { unread(s); return }
  if (s ~ /^project[[:space:]]*\(.*\)[[:space:]]*\.(projectDir|buildFileName|name)/) { unread(s); return }
  if (s ~ /^apply.*from[[:space:]]*[:=]/) { unread(s); return }
  if (s ~ /^include[[:space:](]/) {
    rest = s
    sub(/^include[[:space:]]*/, "", rest)
    accparen = (rest ~ /^\(/)
    acc = s
    last = s
    if (complete()) finish()
    return
  }
  if (s ~ /(^|[^[:alnum:]_.$"\047])include(Flat|Build)?[[:space:](]/) unread(s)
}
function build_line(s,    rest, p, i, c, q, d, a, item, after, ok) {
  if (s ~ /(^|[^[:alnum:]_.$"\047])projects\.[A-Za-z_]/) unread(s)
  rest = s
  while (match(rest, /(^|[^[:alnum:]_$])project[[:space:]]*\(/)) {
    p = RSTART + RLENGTH
    q = ""; d = 1; ok = 0
    for (i = p; i <= length(rest); i++) {
      c = substr(rest, i, 1)
      if (q != "") { if (c == "\\") i++; else if (c == q) q = "" }
      else if (c == dq || c == sq) q = c
      else if (c == "(") d++
      else if (c == ")" && --d == 0) { ok = 1; break }
    }
    if (!ok) { unread(s); return }
    a = trim(substr(rest, p, i - p))
    after = substr(rest, i + 1)
    rest = after
    if (after ~ /^[[:space:]]*\./) { unread(s); continue }
    sub(/^path[[:space:]]*[:=][[:space:]]*/, "", a)
    if (match(a, /^"[^"]*"/) || match(a, "^" sq "[^" sq "]*" sq)) {
      item = substr(a, 2, RLENGTH - 2)
      if (substr(a, 1, 1) == dq && item ~ /\$/) unread(s)
      else printf "project\t%s\t%s\n", item, tidy(s)
    } else unread(s)
  }
}
{
  line = $0
  sub(/\r$/, "", line)
  s = trim(strip(line))
  if (s == "") next
  if (acc != "") {
    acc = acc " " s
    last = s
    if (complete()) finish()
    next
  }
  if (kind == "settings") settings_line(s)
  else build_line(s)
}
END { if (acc != "") unread("<unterminated include> " acc) }
'

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_jvm_pom_awk='
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function tidy(d) { gsub(/\t/, " ", d); gsub(/[[:space:]]+/, " ", d); return d }
function unread(d) { printf "unread\t%s\n", tidy(d) }
function tag(t,    name, closing, selfclose) {
  if (t ~ /^<[?!]/) return
  closing = (t ~ /^<\//)
  selfclose = (t ~ /\/>$/)
  name = t
  sub(/^<\/?/, "", name)
  sub(/[[:space:]\/>].*$/, "", name)
  sub(/^[^:]*:/, "", name)
  if (closing) {
    if (capkind != "" && name == capname) { emit(); capkind = "" }
    if (sp > 0) sp--
    return
  }
  if (selfclose) return
  stk[++sp] = name
  if (name == "module" && stk[sp - 1] == "modules" && (stk[sp - 2] == "project" || stk[sp - 2] == "profile")) { capkind = "module"; capname = name; cap = "" }
  else if (name == "artifactId" && sp == 2 && stk[1] == "project") { capkind = "name"; capname = name; cap = "" }
}
function emit(    v) {
  v = trim(cap)
  if (capkind == "name") { if (v != "" && !seen_name) { seen_name = 1; print "name\t" v } return }
  if (v == "" || v ~ /\$\{/) unread("<module>" v "</module>")
  else printf "module\t%s\t%s\n", v, tidy("<module>" v "</module>")
}
{
  line = $0
  sub(/\r$/, "", line)
  out = ""
  while (line != "") {
    if (incm) {
      i = index(line, "-->")
      if (!i) break
      line = substr(line, i + 3)
      incm = 0
      continue
    }
    i = index(line, "<!--")
    if (!i) { out = out line; break }
    out = out substr(line, 1, i - 1)
    line = substr(line, i + 4)
    incm = 1
  }
  rest = out
  while (match(rest, /<[^<>]*>/)) {
    if (capkind != "") cap = cap substr(rest, 1, RSTART - 1)
    t = substr(rest, RSTART, RLENGTH)
    rest = substr(rest, RSTART + RLENGTH)
    tag(t)
  }
  if (capkind != "") cap = cap rest " "
}
'

jvm_settings_records() {
  [[ -r "$1" ]] || return 0
  awk -v kind=settings "$_jvm_gradle_awk" "$1"
}

jvm_build_records() {
  [[ -r "$1" ]] || return 0
  awk -v kind=build "$_jvm_gradle_awk" "$1"
}

jvm_pom_records() {
  [[ -r "$1" ]] || return 0
  awk "$_jvm_pom_awk" "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'jvm-references.sh is sourced by collectors; it is not a command.\n' >&2
  exit 2
fi
