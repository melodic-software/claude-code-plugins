#!/bin/sh
# bash-format lint entry: report what ShellCheck finds on the lines this change
# adds. It never rewrites a file.
#
#   lint.sh             the staged changes (git runs it as pre-commit)
#   lint.sh --worktree  the uncommitted changes against HEAD, untracked files
#                       included (the opt-in end-of-turn Stop row)
#   lint.sh --resolve [<path>...]  print the lint row, or one per path
#                       (resolve-tool.sh rt_print); runs nothing
#
# The command resolves per file through lib/git-hooks/resolve-tool.sh to the
# ShellCheck adapter in adapters.sh, for a .sh or .bash file with a
# .shellcheckrc or shellcheckrc in its directory or above it, else to nothing;
# a .claude/ecosystems/ record is never run here. Its findings (warning and
# above) become "<path>:<line>: <message>" lines, repo-relative, and only
# those on added lines block (stderr, exit 1). A ShellCheck that exits
# non-zero with no parseable finding fails closed. A staged script since
# deleted from the work tree, or partly staged, is linted from the index. A
# commit whose ShellCheck rc above a staged script differs between the index
# and the work tree is refused. Files under .githooks/ are installed copies and
# are skipped. A missing tool follows the check-placement contract:
# checks.skipmissing, else fail for an agent and a notice for a person.
#
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../../../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail
rt="$here/resolve-tool.sh"
[[ -f "$rt" ]] || rt="$here/../lib/git-hooks/resolve-tool.sh"
# shellcheck source=../../../lib/git-hooks/resolve-tool.sh
. "$rt" || exit 1
# shellcheck source=adapters.sh
. "$here/adapters.sh" || exit 1

resolve=()
if [[ "${1:-}" == --resolve ]]; then
  shift
  for f in "$@"; do
    [[ "$f" == /* ]] || f="$PWD/$f"
    resolve+=("$f")
  done
  set -- --resolve
fi
checks_init pre-commit "$@" || exit 0
if [[ " $CHECKS_ARGS " == *" --resolve "* ]]; then
  rt_print lint "$PWD" ${resolve[@]+"${resolve[@]}"}
  exit 0
fi

candidates=()
while IFS= read -r -d '' f; do
  rt_wants "$f" && candidates+=("$f")
done < <(checks_files)
((${#candidates[@]})) || exit 0

rt_group lint "$PWD" "${candidates[@]}"
checks_refuse_config_drift .shellcheckrc shellcheckrc -- "${candidates[@]}" || exit 1
((RT_GN)) || exit 0

files=()
indexed=()
for ((i = 0; i < RT_GN; i++)); do
  rt_use "$i"
  for f in "${RT_FILES[@]}"; do
    if [[ -f "$f" && ! -L "$f" ]]; then
      if [[ "$CHECKS_MODE" == pre-commit ]] && checks_partly_staged "$f"; then
        indexed+=("$f")
      else
        files+=("$f")
      fi
    elif checks_staged_gone "$f"; then
      indexed+=("$f")
    fi
  done
done
((${#files[@]} + ${#indexed[@]})) || exit 0
rt_require
case $? in
0) ;;
2) exit 1 ;;
*) exit 0 ;;
esac

checks_changed_lines

out="$CHECKS_TMP/shellcheck"
: >"$out"
rc=0

# Identical scripts lint identically when ShellCheck reads nothing else that
# depends on the path: the extension (its dialect fallback), the .shellcheckrc
# nearest the script's directory, and, for a script that sources a file, the
# directory a SCRIPTDIR search path resolves it from. So each distinct (bytes,
# extension, nearest rc) is linted once, from its first path, into $lint; a
# group spread over directories stays whole only when a probe finds nothing it
# sources, else it splits by directory. $copies maps a linted path to each copy,
# which gets its findings under its own path, so its own added lines still decide
# what blocks. Any failure here lints every path. The path-dependent inputs are
# the ones https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md
# lists under RC FILES, source-path and --shell.
lint=(${files[@]+"${files[@]}"})
copies="$CHECKS_TMP/copies"
: >"$copies"
# sc_rcdir <path>: the directory of the .shellcheckrc or shellcheckrc nearest the
# path, up to the top level, in $rcdir; empty when none (the lookup above the top
# level is the same for every path).
sc_rcdir() {
  local d="$1"
  rcdir=
  while [[ "$d" == */* ]]; do
    d="${d%/*}"
    [[ -e "$d/.shellcheckrc" || -e "$d/shellcheckrc" ]] && rcdir="$d" && return
  done
  [[ -e .shellcheckrc || -e shellcheckrc ]] && rcdir=.
  return 0
}
# sc_sources <path>: 0 unless ShellCheck, without any rc, SHELLCHECK_OPTS or the
# script's own directives, reports no source statement (SC1090, SC1091) and no
# error, such as a parse error that hides the rest of the script.
sc_sources() {
  local probe
  probe="$(sed 's/#[[:space:]]*shellcheck/#_/g' -- "$1" |
    (unset SHELLCHECK_OPTS && "$RT_BIN" --norc -s bash -f gcc -S info -) 2>&1)"
  (($? <= 1)) || return 0
  grep -q -e '\[SC109[01]\]' -e ': error: ' <<<"$probe"
}
dedupe_files() {
  local table="$CHECKS_TMP/blobs" i=0 f h ext dir key rep path
  plain=()
  for f in ${files[@]+"${files[@]}"}; do
    [[ "$f" == *[$'\t\n']* ]] || plain+=("$f")
  done
  ((${#plain[@]} > 1)) || return 0
  printf '%s\n' "${plain[@]}" | git hash-object --no-filters --stdin-paths >"$CHECKS_TMP/hashes" || return 1
  : >"$table"
  while IFS= read -r h; do
    f="${plain[i]}"
    ext="${f##*.}"
    sc_rcdir "$f"
    dir=.
    [[ "$f" == */* ]] && dir="${f%/*}"
    printf '%s %s %s\t%s\t%s\n' "$h" "$ext" "$rcdir" "$dir" "$f" >>"$table"
    i=$((i + 1))
  done <"$CHECKS_TMP/hashes"
  ((i == ${#plain[@]})) || return 1
  # A group whose paths sit in more than one directory: its first path, probed.
  awk -F '\t' '{ if (!($1 in first)) first[$1] = $3; else if (dir[$1] != $2) spread[$1] = 1; dir[$1] = $2 }
    END { for (k in spread) print k "\t" first[k] }' "$table" >"$CHECKS_TMP/spread" || return 1
  : >"$CHECKS_TMP/split"
  while IFS=$'\t' read -r key rep; do
    sc_sources "$rep" && printf '%s\n' "$key" >>"$CHECKS_TMP/split"
  done <"$CHECKS_TMP/spread"
  awk -F '\t' -v probed="$CHECKS_TMP/split" '
    BEGIN { while ((got = (getline l < probed)) > 0) apart[l] = 1; if (got < 0) exit 2 }
    { k = ($1 in apart) ? $1 "\t" $2 : $1; if (!(k in rep)) rep[k] = $3; print rep[k] "\t" $3 }' "$table" >"$CHECKS_TMP/reps" || return 1
  lint=()
  while IFS=$'\t' read -r rep path; do
    if [[ "$rep" == "$path" ]]; then
      lint+=("$path")
    else
      printf '%s\t%s\n' "$rep" "$path" >>"$copies"
    fi
  done <"$CHECKS_TMP/reps"
  for f in ${files[@]+"${files[@]}"}; do
    [[ "$f" == *[$'\t\n']* ]] && lint+=("$f")
  done
  return 0
}
if ! dedupe_files; then
  lint=(${files[@]+"${files[@]}"})
  : >"$copies"
fi
# rt_run passes the paths as arguments in chunks under Windows' 32,767-character
# command-line cap (ShellCheck takes its file list only as arguments), and
# returns the highest status.
if ((${#lint[@]})); then
  rt_run "${lint[@]}" >>"$out" 2>&1
  rc=$?
fi
# Each finding of a linted path is repeated for every copy of it, right after.
# rt_run hands a name starting with - over as ./<name>, so the lookup drops ./.
if [[ -s "$copies" ]]; then
  awk -v copies="$copies" '
    BEGIN {
      while ((got = (getline l < copies)) > 0) { t = index(l, "\t"); r = substr(l, 1, t - 1); c[r] = (r in c) ? c[r] "\t" substr(l, t + 1) : substr(l, t + 1) }
      if (got < 0) exit 2
    }
    { print }
    match($0, /:[0-9]+:[0-9]+: /) {
      p = substr($0, 1, RSTART - 1)
      sub(/^\.\//, "", p)
      if (p in c) {
        n = split(c[p], m, "\t")
        for (i = 1; i <= n; i++) print m[i] substr($0, RSTART)
      }
    }' "$out" >"$out.copies"
  copied=$?
  if ((copied == 0)); then
    mv "$out.copies" "$out"
  else
    checks_tool_failed awk "$copied" 'copying the shellcheck findings to identical scripts'
  fi
fi
# A script gone from the work tree or partly staged is read from the index on
# stdin, named "-".
for f in ${indexed[@]+"${indexed[@]}"}; do
  git show ":$f" 2>/dev/null | "$RT_BIN" -x -f gcc -S warning - >"$CHECKS_TMP/one" 2>&1
  one=${PIPESTATUS[1]}
  ((one > rc)) && rc=$one
  escaped="$(printf '%s' "$f" | sed 's/[#&\\]/\\&/g')"
  sed "s#^-:#$escaped:#" "$CHECKS_TMP/one" >>"$out"
done
# ShellCheck's gcc format is "<path>:<line>:<col>: <level>: <message>"; the
# contract line drops the column. Status 1 ("some issues") with no such line
# fails closed, showing ShellCheck's output; a status above 1 is reported
# below unless a finding blocks first.
rt_normalize "$out" "$((rc == 1))" >"$CHECKS_TMP/contract" || exit 1
checks_filter_findings <"$CHECKS_TMP/contract" >"$CHECKS_TMP/blocking"
if [[ -s "$CHECKS_TMP/blocking" ]]; then
  cat "$CHECKS_TMP/blocking" >&2
  printf 'bash-format: fix the findings above, or adjust the repository .shellcheckrc.\n' >&2
  exit 1
fi
if ((rc > 1)); then
  printf 'bash-format: shellcheck failed:\n' >&2
  cat "$out" >&2
  exit 1
fi
exit 0
