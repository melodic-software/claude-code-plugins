#!/usr/bin/env bash
# Check that no skill, agent, reference, doc or prompt states a price, a rate, a
# per-task or per-session cost, or a percentage saving.
#
#   scripts/check-cost-figures.sh          list every offender
#   scripts/check-cost-figures.sh --check  same, explicit form matching the
#                                          sibling gates (exit 1 on any offender)
#
# The rule (.claude/rules/cost-claims.md): text links the costs and pricing
# pages instead of restating a figure. Its two exceptions pass here:
#
#   - a paragraph in a docs/upstream/ record that says "vendor-reported";
#   - a section (heading to next heading) of a file under plugins/*/skills/ that
#     says "list-price estimate" and carries a YYYY-MM-DD date, an x.y.z version
#     and "recheck": a skill's own dated, measured run costs. The setup measured
#     is the one requirement the check cannot read.
#
# What is read: every *.md under the rule's paths, plugins/*/skills/,
# plugins/*/agents/, plugins/*/reference/, docs/ and prompts/, minus fixtures/
# trees, whose samples hold figures on purpose. Code is not prose: code fences
# and `inline code` are skipped. A file scripts/shared-copies.txt lists as a
# generated copy is read through its canonical source.
#
# What is a figure, case-insensitive:
#   - money: a $, € or £ sign before a digit ($4, $0.20, $10/M), or a number
#     before USD, EUR, GBP, dollar(s) or cent(s) (1.67 USD);
#   - a rate multiple: <n>x or <n> times the price or pricing;
#   - a percentage saving: <n>% cheaper / less expensive / lower cost / saving /
#     discount / off the price; costs <n>% less; saves, cuts, reduces or lowers
#     cost, spend, the bill or price by <n>%; cost, spend or price falls or
#     drops by <n>%; saves <n>% of or on the cost; <n>x or <n> times cheaper.
# Deliberately not a figure: a bare number or percentage (a threshold, a score,
# a coverage or cache-hit rate), "<n>% of the cost" (a share of time or work),
# "<n>x the cost", "per million tokens" without an amount, and shell fields such
# as `$1` inside code.
#
# A paragraph is a run of non-blank lines outside a code fence; a heading, a
# table row and a list item each stand alone. Findings count paragraphs.
#
# A file with offenders fails unless scripts/cost-figures-baseline.txt lists it
# as `<path> <count>` and it holds exactly <count>; the baseline only shrinks,
# with the stale guard of scripts/check-spoke-plugin-root.sh. A file whose
# figures are not costs at all (a number-formatting example) is listed in
# scripts/cost-figures-exempt.txt with its reason; an entry whose file no longer
# holds a figure is stale and fails too.
#
# Output follows the check-script contract (scripts/README.md, "The check-script
# contract"): one finding per line on stderr, each naming the fix first; the
# clean-run statement on stdout. Exit: 0 clean, 1 any offender, 2 environment or
# usage (bad argument, unreadable list, malformed entry, failed scan).
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

BASELINE="${COST_FIGURES_BASELINE:-scripts/cost-figures-baseline.txt}"
EXEMPT="${COST_FIGURES_EXEMPT:-scripts/cost-figures-exempt.txt}"
COPIES=scripts/shared-copies.txt
FIX='FIX: delete the figure and link the page that owns it, https://code.claude.com/docs/en/costs#track-your-costs for usage or https://platform.claude.com/docs/en/about-claude/pricing for rates (.claude/rules/cost-claims.md; a docs/upstream/ record labels a post'"'"'s figure vendor-reported, a skill'"'"'s own measured run cost sits in a section labeled list-price estimate with its date, Claude Code version and recheck trigger)'
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
baseline=() exempt=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case
read_list::into baseline "$BASELINE" --comments inline || exit 2
# shellcheck disable=SC2310
read_list::into exempt "$EXEMPT" --comments inline || exit 2

ENTRY_RE='^([^ ]+\.md) ([1-9][0-9]*)$'
declare -A listed=() exempted=()
for entry in ${baseline+"${baseline[@]}"}; do
  if [[ ! "$entry" =~ $ENTRY_RE ]]; then
    printf 'check-cost-figures: %s: "%s" is not "<markdown path> <count>"\n' "$BASELINE" "$entry" >&2
    exit 2
  fi
  listed["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
done
for entry in ${exempt+"${exempt[@]}"}; do
  if [[ ! "$entry" =~ ^[^\ ]+\.md$ ]]; then
    printf 'check-cost-figures: %s: "%s" is not "<markdown path>  # reason"\n' "$EXEMPT" "$entry" >&2
    exit 2
  fi
  exempted["$entry"]=1
done

declare -A canonical=()
if [[ -f "$COPIES" ]]; then
  while read -r src copy _; do
    [[ -n "$src" && "$src" != \#* && -n "${copy:-}" ]] || continue
    canonical["$copy"]="$src"
  done <"$COPIES" || exit 2
fi

# The bracket globs let nullglob drop a docs/ or prompts/ the tree lacks.
shopt -s nullglob
roots=(plugins/*/skills plugins/*/agents plugins/*/reference doc[s] prompt[s])
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
  done < <(find "${roots[@]}" -name fixtures -prune -o -type f -name '*.md' -print0) || exit 2
fi

found=""
if ((${#files[@]} > 0)); then
  # One `<file>\t<line>` per offending paragraph, keyed by its first line.
  found="$(LC_ALL=C awk '
    function figure(t) {
      gsub(/`[^`]*`/, "", t)
      return t ~ money || t ~ amount || t ~ multiple || t ~ pct1 || t ~ pct2 || t ~ pct3 || t ~ pct4 || t ~ cheaper
    }
    function flush(   t) {
      if (buf == "") return
      t = tolower(buf)
      sect = sect " " t
      if (figure(t) && !(upstream && t ~ /vendor-reported/)) held = held file "\t" start "\n"
      buf = ""
    }
    # A section ends at the next heading. Its held paragraphs print unless it
    # meets the measured-run exception.
    function close_section() {
      flush()
      if (held != "" && !(skill && sect ~ /list-price estimate/ && sect ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ && sect ~ /[0-9]+\.[0-9]+\.[0-9]+/ && sect ~ /re-?check/)) printf "%s", held
      held = ""; sect = ""
    }
    function close_file() { close_section(); fence = 0 }
    BEGIN {
      n = "[0-9]+(\\.[0-9]+)?"
      about = "(about |up to |roughly |around |nearly |almost |~)?"
      money = "(^|[^a-z0-9_$\\\\])(\\$|€|£)[0-9]"
      amount = "[0-9] ?(usd|eur|gbp|dollars?|cents?)([^a-z]|$)"
      multiple = n " ?(x|×|times) (the )?([a-z0-9.]+ )?(price|pricing)([^a-z]|$)"
      pct1 = n " ?(%|percent) (cheaper|less expensive|lower (cost|price|spend|bill)|savings?|discount|off (the )?(price|bill|list))"
      pct2 = "((save|saves|saved|saving|savings)|cut(s|ting)?|reduc(e|es|ed|ing|tion)|lower(s|ed|ing)?|drop(s|ped)?) (the |your )?(input |output |token |api |model )?(costs?|spend(ing)?|bills?|prices?)( by| of)? " about n " ?(%|percent)"
      pct3 = "(costs?|prices?|spend(ing)?|bills?) (fall|falls|fell|drop|drops|dropped|goes down|went down|shrinks?) (by )?" about n " ?(%|percent)"
      pct4 = "((save|saves|saved|saving|savings) " about n " ?(%|percent) (of|on|in) (the |your )?(costs?|spend(ing)?|bills?|prices?)|costs? " about n " ?(%|percent) less)"
      cheaper = n " ?(x|×|times) cheaper"
    }
    FNR == 1 {
      close_file(); file = FILENAME
      upstream = file ~ /^docs\/upstream\//
      skill = file ~ /^plugins\/[^\/]+\/skills\//
    }
    # A fence closes only on a bare run of its opener character at least as
    # long, so a four-backtick example can hold a three-backtick block.
    /^[ \t]*(```|~~~)/ {
      s = $0; sub(/^[ \t]*/, "", s); c = substr(s, 1, 1); k = 0
      while (substr(s, k + 1, 1) == c) k++
      if (!fence) { flush(); fence = 1; fch = c; flen = k }
      else if (c == fch && k >= flen && substr(s, k + 1) ~ /^[ \t]*$/) fence = 0
      next
    }
    fence { next }
    /^[ \t]*$/ { flush(); next }
    /^[ \t]*#/ { close_section(); buf = $0; start = FNR; flush(); next }
    /^[ \t]*[|]/ { flush(); buf = $0; start = FNR; flush(); next }
    /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/ { flush() }
    { if (buf == "") start = FNR; buf = buf " " $0 }
    END { close_file() }
  ' "${files[@]}")" || {
    printf 'check-cost-figures: the paragraph scan failed\n' >&2
    exit 2
  }
fi

declare -A hits=() lines=()
while IFS=$'\t' read -r f n; do
  [[ -n "$f" ]] || continue
  hits["$f"]=$((${hits["$f"]:-0} + 1))
  lines["$f"]+="$f:$n: $FIX. The paragraph states a price, rate, cost or percentage saving."$'\n'
done <<<"$found"

offenders=()
for f in "${!hits[@]}"; do
  [[ -z "${exempted[$f]:-}" ]] || continue
  n="${hits[$f]}"
  if [[ -z "${listed[$f]:-}" ]] || ((n > listed[$f])); then
    while IFS= read -r line; do
      [[ -z "$line" ]] || offenders+=("$line")
    done <<<"${lines[$f]}"
    [[ -z "${listed[$f]:-}" ]] ||
      offenders+=("$f: FIX: link the costs or pricing page instead of the new figure; $BASELINE allows ${listed[$f]} and the file has $n")
  elif ((n < listed[$f])); then
    offenders+=("$f: FIX: lower its count in $BASELINE to $n; the file has $n paragraph(s) with a cost figure, the baseline lists ${listed[$f]}")
  fi
done
for f in "${!listed[@]}"; do
  [[ -z "${hits[$f]:-}" ]] || continue
  if [[ -f "$f" ]]; then
    offenders+=("$f: FIX: delete its line from $BASELINE; the file states no cost figure now")
  else
    offenders+=("$f: FIX: delete its line from $BASELINE; the file does not exist")
  fi
done
for f in "${!exempted[@]}"; do
  [[ -z "${hits[$f]:-}" ]] || continue
  offenders+=("$f: FIX: delete its line from $EXEMPT; the file holds no figure to exempt")
done

if ((${#offenders[@]} == 0)); then
  printf 'check-cost-figures: no cost figure in %d skill, agent, reference, doc and prompt file(s), outside %d baselined and %d exempt file(s).\n' \
    "${#files[@]}" "${#listed[@]}" "${#exempted[@]}"
  exit 0
fi

printf '%s\n' "${offenders[@]}" | LC_ALL=C sort -u >&2
printf 'check-cost-figures: %d finding(s); the rule is in .claude/rules/cost-claims.md.\n' \
  "${#offenders[@]}" >&2
exit 1
