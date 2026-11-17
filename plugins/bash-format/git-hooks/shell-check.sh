#!/bin/sh
# bash-format pre-commit check: format the staged shell scripts the repository
# opted in to format, then report what ShellCheck finds on the lines this commit
# adds.
#
#   shell-check.sh               the staged changes (git runs it as pre-commit)
#   shell-check.sh --worktree    the uncommitted changes against HEAD, untracked
#                                files included, reported without rewriting
#                                (the opt-in end-of-turn Stop row)
#
# Pre-commit: when shfmt can run, a partly staged shell script an .editorconfig
# section governs is refused before anything is rewritten (re-staging a rewrite
# would stage its unstaged hunks too). Then shfmt formats the staged .sh and
# .bash files such a section governs (see git-hooks/shfmt-rewrite.sh), the
# rewritten paths print on stdout and are re-staged, and the ShellCheck findings
# (warning and above) print as "<path>:<line>: <message>" on stderr, exit 1, only
# for lines the commit adds. A staged script since deleted from the work tree, or
# partly staged and left unrewritten, is checked from the index and never
# rewritten.
#
# The repository's own .shellcheckrc and .editorconfig govern; the plugin ships
# none, and both are read from the work tree, so a pre-commit run is refused when
# either one above a staged script differs between the index and the work tree.
# Files under .githooks/ are installed copies and are skipped. A missing
# tool follows the check-placement contract: checks.skipmissing, else fail for an
# agent and a notice for a person; a tool that is skipped only drops its own half
# (no shfmt: no rewrite; no shellcheck: no findings). The rule holds in every
# mode.
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
# shellcheck source=shfmt-rewrite.sh
. "$here/shfmt-rewrite.sh" || exit 1

checks_init pre-commit "$@" || exit 0

# need <tool> <install>: 0 when the tool is usable. When it is missing, the
# contract decides: an agent's run fails here; a skip key or a person's notice
# returns 1 so the other half of the check still runs.
need() {
  command -v "$1" >/dev/null 2>&1 && return 0
  (checks_require_tool "$1" "$2") || exit 1
  return 1
}

files=()
indexed=()
while IFS= read -r -d '' f; do
  case "$f" in
  .githooks/*) continue ;;
  *.sh | *.bash) ;;
  *) continue ;;
  esac
  if [[ -f "$f" && ! -L "$f" ]]; then
    files+=("$f")
  elif checks_staged_gone "$f"; then
    indexed+=("$f")
  fi
done < <(checks_files)
((${#files[@]} + ${#indexed[@]})) || exit 0
checks_refuse_config_drift .editorconfig .shellcheckrc -- ${files[@]+"${files[@]}"} ${indexed[@]+"${indexed[@]}"} || exit 1

if [[ "$CHECKS_MODE" == pre-commit ]] && ((${#files[@]})); then
  governed=()
  for f in "${files[@]}"; do
    shfmt_governed "$f" && governed+=("$f")
  done
  if ((${#governed[@]})); then
    can_rewrite=1
    need shfmt "see https://github.com/mvdan/sh#shfmt" || can_rewrite=0
    need jq "see https://jqlang.org/download/" || can_rewrite=0
    if ((can_rewrite)); then
      # Only the governed shell files are refused, not every staged path, which
      # is what checks_refuse_partly_staged would walk.
      refused=0
      for f in "${governed[@]}"; do
        if checks_partly_staged "$f"; then
          printf '%s: partly staged; format it or stage it fully, then commit\n' "$f" >&2
          refused=1
        fi
      done
      ((refused)) && exit 1
      for f in "${governed[@]}"; do
        shfmt_rewrite "$f"
      done
      [[ -z "$SHFMT_NOTE" ]] || printf '%s\n' "$SHFMT_NOTE" >&2
      checks_restage "${governed[@]}"
    fi
  fi
  # A partly staged script left unrewritten is linted as staged, from the index.
  whole=()
  for f in "${files[@]}"; do
    if checks_partly_staged "$f"; then
      indexed+=("$f")
    else
      whole+=("$f")
    fi
  done
  files=(${whole[@]+"${whole[@]}"})
fi

need shellcheck "see https://github.com/koalaman/shellcheck#installing" || exit 0

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
    (unset SHELLCHECK_OPTS && shellcheck --norc -s bash -f gcc -S info -) 2>&1)"
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
# Windows caps a whole command line at 32,767 characters, and ShellCheck 0.11.0
# takes its file list only as arguments, so the paths go in batches whose
# summed length, plus a separator each, stays under this budget; the rest of
# the cap is left for the program path, the flags and any quoting. Each batch
# appends to $out, and the highest status wins.
sc_budget=24000
shellcheck_batch() {
  shellcheck -x -f gcc -S warning -- "$@" >>"$out" 2>&1
  local batch_rc=$?
  ((batch_rc > rc)) && rc=$batch_rc
  return 0
}
batch=()
size=0
for f in ${lint[@]+"${lint[@]}"}; do
  if ((${#batch[@]} && size + ${#f} + 1 > sc_budget)); then
    shellcheck_batch "${batch[@]}"
    batch=()
    size=0
  fi
  batch+=("$f")
  size=$((size + ${#f} + 1))
done
((${#batch[@]})) && shellcheck_batch "${batch[@]}"
# Each finding of a linted path is repeated for every copy of it, right after.
if [[ -s "$copies" ]]; then
  awk -v copies="$copies" '
    BEGIN {
      while ((got = (getline l < copies)) > 0) { t = index(l, "\t"); r = substr(l, 1, t - 1); c[r] = (r in c) ? c[r] "\t" substr(l, t + 1) : substr(l, t + 1) }
      if (got < 0) exit 2
    }
    { print }
    match($0, /:[0-9]+:[0-9]+: /) && (substr($0, 1, RSTART - 1) in c) {
      n = split(c[substr($0, 1, RSTART - 1)], m, "\t")
      for (i = 1; i <= n; i++) print m[i] substr($0, RSTART)
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
  git show ":$f" 2>/dev/null | shellcheck -x -f gcc -S warning - >"$CHECKS_TMP/one" 2>&1
  one=${PIPESTATUS[1]}
  ((one > rc)) && rc=$one
  escaped="$(printf '%s' "$f" | sed 's/[#&\\]/\\&/g')"
  sed "s#^-:#$escaped:#" "$CHECKS_TMP/one" >>"$out"
done
# ShellCheck's gcc format is "<path>:<line>:<col>: <level>: <message>"; the
# contract line drops the column.
sed -n -e 's/^\(.*\):\([0-9][0-9]*\):[0-9][0-9]*: \(.*\)$/\1:\2: \3/p' <"$out" | checks_filter_findings >"$CHECKS_TMP/blocking"
# A failed sed leaves findings out, so it fails the hook; 141 means the filter
# stopped first, and the filter reports.
contract=${PIPESTATUS[0]}
((contract == 0 || contract == 141)) || checks_tool_failed sed "$contract" 'reading the shellcheck findings'
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
