#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
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
  found="$(LC_ALL=C awk '
    function figure(t) {
      if (t !~ /[0-9]/) return 0
      if (t !~ /[$€£%]|percent|usd|eur|gbp|dollar|cent|price|pricing|cheaper/) return 0
      gsub(/`[^`]*`/, "", t)
      if (t ~ money || t ~ amount) return 1
      if (t ~ /%|percent/ && (t ~ pct1 || t ~ pct2 || t ~ pct3 || t ~ pct4)) return 1
      if (t ~ /price|pricing/ && t ~ multiple) return 1
      if (t ~ /cheaper/ && t ~ cheaper) return 1
      return 0
    }
    function rate(t) {
      gsub(/`[^`]*`/, "", t)
      return t ~ multiple || t ~ rate1 || t ~ rate2 || t ~ rate3
    }
    # A rate prints at once: the measured-run exception covers run costs only.
    function flush(   t) {
      if (buf == "") return
      t = tolower(buf)
      if (skill) {
        if (!s_lpe && index(t, "list-price estimate") > 0) s_lpe = 1
        if (!s_date && t ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) s_date = 1
        if (!s_ver && t ~ /[0-9]+\.[0-9]+\.[0-9]+/) s_ver = 1
        if (!s_recheck && t ~ /re-?check/) s_recheck = 1
      }
      if (figure(t) && !(upstream && t ~ /vendor-reported/)) {
        if (rate(t)) print file "\t" start
        else held = held file "\t" start "\n"
      }
      buf = ""
    }
    # A section ends at the next heading. Its held paragraphs print unless it
    # meets the measured-run exception.
    function close_section() {
      flush()
      if (held != "" && !(skill && s_lpe && s_date && s_ver && s_recheck)) printf "%s", held
      held = ""; s_lpe = 0; s_date = 0; s_ver = 0; s_recheck = 0
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
      per = " ?(/|per) ?(1m|m|mtok|million|1k|k|thousand)([^a-z]|$)"
      rate1 = "(\\$|€|£)" n per
      rate2 = n " ?(usd|eur|gbp|dollars?|cents?)" per
      rate3 = "(\\$|€|£)" n "[a-z ]* per (1m |1k |million |thousand )?((input|output|cached?|cache[- ]read|cache[- ]write) )?tokens?"
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
    # A heading needs a space or the line end after its #s, so a wrapped line
    # opening with an issue reference (#123) stays prose.
    /^[ \t]*#+([ \t]|$)/ { close_section(); buf = $0; start = FNR; flush(); next }
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
