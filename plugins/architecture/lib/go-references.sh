#!/usr/bin/env bash
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
