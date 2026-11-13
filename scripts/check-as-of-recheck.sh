#!/usr/bin/env bash
# Check that every as-of date in a skill, agent or reference file sits in a
# paragraph that also carries a recheck trigger.
#
#   scripts/check-as-of-recheck.sh          list every offender
#   scripts/check-as-of-recheck.sh --check  same, explicit form matching the
#                                           sibling gates (exit 1 on any offender)
#
# The rule (.claude/rules/skill-bodies-state-current-rules.md): a stored value,
# a number or string copied or measured from upstream, keeps an as-of date and a
# recheck trigger; a pointer carries neither. So an as-of date alone is always a
# defect: either the trigger is missing or the date should not be there.
#
# What is read: every *.md under plugins/*/skills/, plugins/*/agents/ and
# plugins/*/reference/, minus evals/ and fixtures/ trees, whose samples hold the
# defect on purpose. A file scripts/shared-copies.txt lists as a generated copy
# is read through its canonical source instead, the one file to edit.
#
# A paragraph is a run of non-blank lines outside a code fence; a heading, a
# table row and a list item each stand alone. It is an offender when it holds
# `as of YYYY-MM-DD` (also `as-of`, `As of:`, bold or italic around the date,
# the date on the next line) and no `recheck` / `re-check`, unless the very next
# paragraph opens with one (an `As of:` line followed by a `Recheck when:` line).
#
# A file with offenders fails unless scripts/as-of-recheck-baseline.txt lists it
# as `<path> <count>` and it holds exactly <count>. A count above the baseline is
# a new offender; a count below it, or a listed file that is gone or clean, is
# stale. Either way the entry must be updated or removed, so the baseline only
# shrinks.
#
# Output follows the check-script contract (scripts/README.md, "The check-script
# contract"): one finding per line on stderr, each naming the fix first; the
# clean-run statement on stdout. Exit: 0 clean, 1 any offender, 2 environment or
# usage (bad argument, unreadable baseline, malformed entry, failed scan).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# CHECK_DATA_ROOT: the tree to check, when it is not the one holding this
# script (the pre-push hook runs a merge-base copy against the branch).
cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

BASELINE="${AS_OF_RECHECK_BASELINE:-scripts/as-of-recheck-baseline.txt}"
COPIES=scripts/shared-copies.txt
FIX='FIX: add a recheck trigger ("Recheck when: <event>") to this paragraph if it stores a copied or measured value, or delete the as-of date if it only points at a source'
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
baseline=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case
read_list::into baseline "$BASELINE" --comments inline || exit 2

ENTRY_RE='^([^ ]+\.md) ([1-9][0-9]*)$'
declare -A listed=()
for entry in ${baseline+"${baseline[@]}"}; do
  if [[ ! "$entry" =~ $ENTRY_RE ]]; then
    printf 'check-as-of-recheck: %s: "%s" is not "<markdown path> <count>"\n' "$BASELINE" "$entry" >&2
    exit 2
  fi
  listed["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
done

declare -A canonical=()
if [[ -f "$COPIES" ]]; then
  while read -r src copy _; do
    [[ -n "$src" && "$src" != \#* && -n "${copy:-}" ]] || continue
    canonical["$copy"]="$src"
  done <"$COPIES" || exit 2
fi

shopt -s nullglob
roots=(plugins/*/skills plugins/*/agents plugins/*/reference)
shopt -u nullglob

declare -A seen=()
files=()
if ((${#roots[@]} > 0)); then
  while IFS= read -r -d '' f; do
    f="${f#./}"
    f="${canonical[$f]:-$f}"
    [[ -z "${seen[$f]:-}" && -f "$f" ]] || continue
    seen["$f"]=1
    files+=("$f")
  done < <(find "${roots[@]}" \( -name evals -o -name fixtures \) -prune -o -type f -name '*.md' -print0) || exit 2
fi

found=""
if ((${#files[@]} > 0)); then
  # One `<file>\t<line>` per offending paragraph, keyed by its first line.
  found="$(LC_ALL=C awk '
    function opens_with_trigger(t) { return t ~ ("^[ \t]*(#+[ \t]*)?([-*+]|[0-9]+[.)])?[ \t]*[*_]*(" trig ")") }
    function flush(   t) {
      if (buf == "") return
      t = tolower(buf)
      if (pending != "") {
        if (!opens_with_trigger(t)) print pending
        pending = ""
      }
      if (t ~ stamp && t !~ trig) pending = file "\t" start
      buf = ""
    }
    function close_file() { flush(); if (pending != "") print pending; pending = ""; fence = 0 }
    BEGIN {
      stamp = "as[ -]of:?[ *_]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"
      trig = "re-?check"
    }
    # The last paragraph of the previous file closes before `file` moves on.
    FNR == 1 { close_file(); file = FILENAME }
    # A fence closes only on a bare run of its opener character at least as
    # long, so a four-backtick example can hold a three-backtick block.
    /^[ \t]*(```|~~~)/ {
      s = $0; sub(/^[ \t]*/, "", s); c = substr(s, 1, 1); n = 0
      while (substr(s, n + 1, 1) == c) n++
      if (!fence) { flush(); fence = 1; fch = c; flen = n }
      else if (c == fch && n >= flen && substr(s, n + 1) ~ /^[ \t]*$/) fence = 0
      next
    }
    fence { next }
    /^[ \t]*$/ { flush(); next }
    # A heading needs a space or the line end after its #s, so a wrapped line
    # opening with an issue reference (#123) stays in its paragraph.
    /^[ \t]*(#+([ \t]|$)|[|])/ { flush(); buf = $0; start = FNR; flush(); next }
    /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ { flush() }
    { if (buf == "") start = FNR; buf = buf " " $0 }
    END { close_file() }
  ' "${files[@]}")" || {
    printf 'check-as-of-recheck: the paragraph scan failed\n' >&2
    exit 2
  }
fi

declare -A hits=() lines=()
while IFS=$'\t' read -r f n; do
  [[ -n "$f" ]] || continue
  hits["$f"]=$((${hits["$f"]:-0} + 1))
  lines["$f"]+="$f:$n: $FIX. The paragraph holds an as-of date and no recheck trigger."$'\n'
done <<<"$found"

offenders=()
for f in "${!hits[@]}"; do
  n="${hits[$f]}"
  if [[ -z "${listed[$f]:-}" ]] || ((n > listed[$f])); then
    while IFS= read -r line; do
      [[ -z "$line" ]] || offenders+=("$line")
    done <<<"${lines[$f]}"
    [[ -z "${listed[$f]:-}" ]] ||
      offenders+=("$f: FIX: give the new paragraph its trigger; $BASELINE allows ${listed[$f]} and the file has $n")
  elif ((n < listed[$f])); then
    offenders+=("$f: FIX: lower its count in $BASELINE to $n; the file has $n paragraph(s) with an as-of date and no trigger, the baseline lists ${listed[$f]}")
  fi
done
for f in "${!listed[@]}"; do
  [[ -z "${hits[$f]:-}" ]] || continue
  if [[ -f "$f" ]]; then
    offenders+=("$f: FIX: delete its line from $BASELINE; every as-of date in it now has a recheck trigger")
  else
    offenders+=("$f: FIX: delete its line from $BASELINE; the file does not exist")
  fi
done

if ((${#offenders[@]} == 0)); then
  printf 'check-as-of-recheck: every as-of date in %d skill, agent and reference file(s) has a recheck trigger, outside %d baselined file(s).\n' \
    "${#files[@]}" "${#listed[@]}"
  exit 0
fi

printf '%s\n' "${offenders[@]}" | LC_ALL=C sort -u >&2
printf 'check-as-of-recheck: %d finding(s); the rule is in .claude/rules/skill-bodies-state-current-rules.md.\n' \
  "${#offenders[@]}" >&2
exit 1
