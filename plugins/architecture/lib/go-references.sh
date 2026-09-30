#!/usr/bin/env bash
# Reader for Go manifests: go.mod and go.work.
#
# WHY. map-dependencies cites a Go module's declared requirements and the local
# modules its replace directives point at. Both files are line oriented: one
# directive per line, or a parenthesized block of them.
#
# Sourced, not executed. Executing it exits 2.
#
#   go_mod_records <go.mod>
#     One line per fact, tab separated:
#       module<TAB>path                             the module directive
#       require<TAB>path<TAB>version<TAB>declaration
#       replace<TAB>old<TAB>target<TAB>local<TAB>declaration
#                                                   local is 1 when target
#                                                   starts with ./, ../ or /
#       unread<TAB>declaration                      a directive shape skipped
#   go_work_records <go.work>
#     use<TAB>dir<TAB>declaration, and unread lines. A go.work replace is
#     unread: the reader does not apply it.
#     declaration is the line as written, comment removed. The go, toolchain,
#     godebug, exclude, retract, tool and ignore directives carry no
#     dependency and give no line. Any other directive is unread.
#
# Portability: bash plus POSIX awk.
# shellcheck shell=bash

# shellcheck disable=SC2016 # an awk program: $0 belongs to awk, not the shell.
_go_awk='
function unread(decl) { printf "unread\t%s\n", decl }
function unq(s) { if (s ~ /^(".*"|`.*`)$/) s = substr(s, 2, length(s) - 2); return s }
function quiet(d) { return d ~ /^(go|toolchain|godebug|exclude|retract|tool|ignore)$/ }
function known(d) { return (kind == "mod" && d ~ /^(module|require|replace)$/) || (kind == "work" && d == "use") }
function handle(d, rest, decl,    n, f, idx, l, r, nl, nr, t) {
  if (quiet(d)) return
  n = split(rest, f, " ")
  if (kind == "mod" && d == "module" && n == 1) { print "module\t" unq(f[1]); return }
  if (kind == "mod" && d == "require" && n == 2) { printf "require\t%s\t%s\t%s\n", unq(f[1]), f[2], decl; return }
  if (kind == "work" && d == "use" && n == 1) { printf "use\t%s\t%s\n", unq(f[1]), decl; return }
  if (kind == "mod" && d == "replace") {
    idx = index(rest, "=>")
    if (idx > 0) {
      nl = split(substr(rest, 1, idx - 1), l, " ")
      nr = split(substr(rest, idx + 2), r, " ")
      if (nl >= 1 && nl <= 2 && nr >= 1 && nr <= 2) {
        t = unq(r[1])
        printf "replace\t%s\t%s\t%d\t%s\n", unq(l[1]), t, (t ~ /^(\.\/|\.\.\/|\/)/) ? 1 : 0, decl
        return
      }
    }
  }
  unread(decl)
}
{
  line = $0
  sub(/\r$/, "", line)
  sub(/(^|[[:space:]])\/\/.*$/, "", line)
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
  if (line == "") next
  if (block != "") {
    if (line == ")") block = ""
    else if (!skipblock) handle(block, line, line)
    next
  }
  d = line
  sub(/[[:space:]].*$/, "", d)
  rest = substr(line, length(d) + 1)
  gsub(/^[[:space:]]+/, "", rest)
  if (rest == "(") {
    block = d
    skipblock = 0
    if (!quiet(d) && !known(d)) { unread(line); skipblock = 1 }
    next
  }
  handle(d, rest, line)
}
END { if (block != "") unread("<unterminated block: " block " (>") }
'

go_mod_records() {
  [[ -r "$1" ]] || return 0
  awk -v kind=mod "$_go_awk" "$1"
}

go_work_records() {
  [[ -r "$1" ]] || return 0
  awk -v kind=work "$_go_awk" "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'go-references.sh is sourced by collectors; it is not a command.\n' >&2
  exit 2
fi
