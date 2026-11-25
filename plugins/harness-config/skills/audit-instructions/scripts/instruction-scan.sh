#!/usr/bin/env bash

set -uo pipefail

usage() {
  cat <<'EOF'
instruction-scan.sh: mark I6/I8/I10/I23/I25/I27/I28/I38/I40 instruction candidates in given files.

Usage: instruction-scan.sh [--count | --i6-counts] [--body-only] [--help] FILE...

  FILE...       print one candidate row (file:line:check-id) per match; exit 0
  --count       print the integer candidate count only; exit 0
  --i6-counts   print `I6 raw=<n> surviving=<n>` only: raw is the per-line
                rule (prohibition token, no rationale marker on the line),
                surviving is what the I6 sentence gates emit; exit 0
  --body-only   skip YAML frontmatter, so no row can point at a description,
                when_to_use, or a trigger phrase quoted in one; exit 0
  --help        this message

I6 selects per sentence: the prohibition opens the sentence, no paired
positive or rationale marker sits in it, soft-wrapped lines are joined first,
and frontmatter, fenced code, table rows, and headings are never read.

I8 pattern families (model-era candidates; model lane adjudicates): I8-a
instructed self-check, I8-b conservative-reporting, I8-c don't-think /
don't-reason, I8-f think-carefully steer, I8-g keep-going exhortation. I23 marks self-estimated context-budget phrasing. I27 marks
effort-for-brevity candidates (effort-lowering directive paired with a brevity
token on one line). I28 families: I28-a forced-compliance emphasis
(case-sensitive), I28-b blanket tool defaults. I25: retired sampling
parameters. I38: progress-update suppressors. I40: own-repository history
references (#N, PR #N) in agents/*.md files, outside code spans, owner/repo#N,
TODO(#N), fenced or indented code, and pointer-record blocks.

Advisory: always exits 0 (candidates never fail the run). Requires grep, tr,
and awk (exit 2 when one is absent). Seeds the candidate set of the audit-instructions
skill; the per-surface lane refines every candidate against reference/criteria.md.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
*) ;;
esac

for tool in grep tr awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool required" >&2
    exit 2
  fi
done

mode="report"
body_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --count)
    mode="count"
    shift
    ;;
  --body-only)
    body_only=1
    shift
    ;;
  --i6-counts)
    mode="i6-counts"
    shift
    ;;
  *) break ;;
  esac
done

WB_L="(^|[^[:alnum:]_])"
WB_R='([^[:alnum:]_]|$)'
RATIONALE_ERE="because|${WB_L}since${WB_R}|${WB_L}so that${WB_R}|${WB_L}so it${WB_R}|${WB_L}so the${WB_R}|${WB_L}to avoid${WB_R}|${WB_L}otherwise${WB_R}|${WB_L}in order to${WB_R}|${WB_L}rationale${WB_R}|${WB_L}reason${WB_R}"
I6_CUE_ALT="never|do not|don('|’)?t|must ?not|mustn('|’)?t|should ?not|shouldn('|’)?t"
I6_PAIRED_ERE="${WB_L}(instead|rather than|prefer(s|red|ring)?|in place of|in favou?r of)${WB_R}"
I6_CLAUSE_STOPWORDS=" the a an and or but nor so yet if unless until when while where which who whose that this these those it its they their them we our us you your he she his her i is are was were be been being as at by for from in into of on onto to with without not no never nor don't do does did doing ever even because since though although however therefore thus hence per via plus minus other others such same both all any each every more most less least than there here what how why "
I6_CLAUSE_TRANSPARENT=" just simply always then also still only first next now again finally "
I10_ERE="(show|explain|reproduce|echo|transcribe|verbalize|narrate|share|describe) (your |the )?(thinking|reasoning|thought process|chain of thought)"
I10_ERE="${I10_ERE}|think out loud|walk (me|us) through your (thinking|reasoning)|reasoning_extraction|chain[- ]of[- ]thought"
I10_ERE="${I10_ERE}|<scratchpad>([^/]|\$)|(think|reason|work (it |this |things )?out|work through)[^.]{0,40}scratchpad|scratchpad[^.]{0,40}(think|reason|work (it |this |things )?out|work through)"
I38_ERE="hold (all |any |your |the )?(findings|results|updates|output)( until| for)|(don('|’)?t|do not|never) narrate"
I38_ERE="${I38_ERE}|no (interim|intermediate|progress) (updates|messages|output|status|notes)|(stay|remain|work) silent(ly)? until"
I38_ERE="${I38_ERE}|(don('|’)?t|do not|never) (send|give|post|write) (any )?(interim|intermediate|progress) (updates|messages|notes|status)"
I8_A_ERE="double[- ]check|${WB_L}re[- ]?verif|final verification step|(sub)?agent to verify|have (a |an )?(sub)?agent verify|verifier (sub)?agent|verify your (own )?work"
I8_B_ERE="be conservative|(only report|report only) (the )?(high|critical)|(don('|’)?t|do not) nitpick"
I8_C_ERE="(do not|don('|’)?t) (think|reason)|without thinking|skip the reasoning"
I8_F_ERE="think (very |really )?(carefully|hard|harder|deeply|thoroughly|step[- ]by[- ]step)|${WB_L}ultrathink${WB_R}"
I8_G_DONE="(it('|’)?s |you('|’)?re |everything is |the (task|work) is )?(done|finished|complete)${WB_R}"
I8_G_ERE="(keep going|keep working|continue|loop) until ${I8_G_DONE}|keep going( no matter what|[.!])|(don('|’)?t|do not|never) (be lazy|give up)"
I23_ERE="context (is |gets |getting |grows )?(heavy|tight|saturated|exhausted)|heavy context"
I23_ERE="${I23_ERE}|(running|runs|run) (out of|low on) context|low on context"
I23_ERE="${I23_ERE}|remaining[- ](context|window|tokens)|context[- ](budget|percentage|occupancy|countdown)|token[- ](budget|countdown)"
I23_ERE="${I23_ERE}|(check|checking|watch|watching|monitor|monitoring) (the |your )?/context|/context output"
I23_ERE="${I23_ERE}|(final|last) (third|quarter|half) of (the|your|its) window|window position"
I23_ERE="${I23_ERE}|(nearing|approaching) (the )?(context|token)[- ](limit|cap|budget|window)"
I27_EFFORT_ERE="(lower|reduc|decreas|dropp?)(e|ed|es|ing|s)? (the |your )?effort" # spellchecker:disable-line
I27_BREVITY_ERE="${WB_L}short|${WB_L}brief|${WB_L}concise|${WB_L}terse|${WB_L}length|verbos|${WB_L}wordy"
I28_A_ERE="CRITICAL:|IMPORTANT:|(You|you) MUST|MANDATORY|ALWAYS use|NEVER skip"
I28_B_ERE="${WB_L}default to (using|running|calling)${WB_R}|if in doubt,? use|${WB_L}always use${WB_R}|use even when"
I25_ERE="${WB_L}temperature${WB_R}|${WB_L}top_p${WB_R}|${WB_L}top_k${WB_R}"
I40_REF_ERE="(^|[^[:alnum:]_&/.#-])#[0-9]+([^[:alnum:]_]|\$)|${WB_L}(pr|pull request)s? #?[0-9]+${WB_R}"
I40_ASOF_ERE="as[- ]of[^0-9]{0,24}[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"
I40_RECHECK_ERE="${WB_L}re-?check"

# shellcheck disable=SC2016 # an awk program: its $0 is awk's, not the shell's
SCAN_AWK='
function frontmatter_end(p,   line, n) {
  if ((getline line < p) <= 0) { close(p); return 0 }
  n = 1
  if (line !~ /^---[[:space:]]*$/) { close(p); return 0 }
  while ((getline line < p) > 0) {
    n++
    if (line ~ /^---[[:space:]]*$/) { close(p); return n }
  }
  close(p)
  return n
}
BEGIN { nfam = split(ids, id, " "); total = 0 }
substr($0, 1, 1) == "\002" { order[++nfiles] = substr($0, 2); next }
substr($0, 1, 1) == "\001" { fam = substr($0, 2) + 0; next }
{
  z = index($0, "\003")
  if (z) { path = substr($0, 1, z - 1); hit = substr($0, z + 1) }
  else if ($0 ~ /^Binary file .* matches$/) { path = substr($0, 13, length($0) - 20); hit = $0 }
  else next
  c = index(hit, ":")
  if (c) { lineno = substr(hit, 1, c - 1); text = substr(hit, c + 1) } else { lineno = hit; text = hit }
  if (id[fam] == "I27" && tolower(text) !~ brevity) next
  key = path SUBSEP fam
  if ((key SUBSEP lineno) in seen) next
  seen[key SUBSEP lineno] = 1
  hits[key] = hits[key] "\n" lineno
}
END {
  for (i = 1; i <= nfiles; i++) {
    p = order[i]
    if (mode == "merge") { print "@FILE"; print p }
    for (f = 1; f <= nfam; f++) {
      key = p SUBSEP f
      if (!(key in hits)) continue
      if (body_only && !(p in fm)) fm[p] = frontmatter_end(p)
      n = split(substr(hits[key], 2), ls, "\n")
      for (j = 1; j <= n; j++) {
        if (body_only && ls[j] ~ /^[0-9]+$/ && ls[j] + 0 <= fm[p]) continue
        total++
        if (mode != "count") print p ":" ls[j] ":" id[f]
      }
    }
  }
  if (mode == "count") print total
}'

files=()
for file in "$@"; do
  [[ -f "$file" ]] && files+=("$file")
done

chunk_start=()
chunk_len=()
start=0
len=0
size=0
for ((i = 0; i < ${#files[@]}; i++)); do
  n=$((${#files[i]} + 3))
  if ((len > 0 && size + n > 24000)); then
    chunk_start+=("$start")
    chunk_len+=("$len")
    start=$i
    len=0
    size=0
  fi
  len=$((len + 1))
  size=$((size + n))
done
if ((len > 0)); then
  chunk_start+=("$start")
  chunk_len+=("$len")
fi

run_family() {
  local idx="$1" flags="$2" ere="$3" c
  printf '\001%s\n' "$idx"
  for ((c = 0; c < ${#chunk_start[@]}; c++)); do
    grep "$flags" --null -e "$ere" -- "${files[@]:chunk_start[c]:chunk_len[c]}" 2>/dev/null
  done
}

run_i40() {
  local idx="$1" c f agents
  printf '\001%s\n' "$idx"
  for ((c = 0; c < ${#chunk_start[@]}; c++)); do
    agents=()
    for f in "${files[@]:chunk_start[c]:chunk_len[c]}"; do
      [[ "$f" =~ (^|[/\\])agents[/\\][^/\\]*\.md$ ]] && agents+=("$f")
    done
    [[ ${#agents[@]} -gt 0 ]] || continue
    LC_ALL=C awk -v ref="$I40_REF_ERE" -v asof="$I40_ASOF_ERE" \
      -v recheck="$I40_RECHECK_ERE" '
      function cited(n) {
        return blk ~ ("[a-z0-9_.-]+/[a-z0-9_.-]+#" n "([^0-9]|$)") ||
          blk ~ ("/(issues|pull)/" n "([^0-9]|$)")
      }
      # 1 when the line holds a reference the block does not cite upstream.
      function own_ref(s,   m) {
        while (match(s, ref)) {
          m = substr(s, RSTART, RLENGTH)
          gsub(/[^0-9]/, "", m)
          if (!cited(m)) return 1
          s = substr(s, RSTART + RLENGTH)
        }
        return 0
      }
      function flush(   k) {
        if (nb > 0 && !(blk ~ asof && blk ~ recheck))
          for (k = 1; k <= nb; k++) if (own_ref(hl[k])) printf "%s\003%s:\n", cur, hit[k]
        nb = 0; blk = ""
      }
      # Drop each code span: a backtick run up to the next run of the same
      # length. An unmatched run is literal text.
      function strip_spans(s,   out, run, rest, k) {
        out = ""
        while (match(s, /`+/)) {
          run = substr(s, RSTART, RLENGTH)
          out = out substr(s, 1, RSTART - 1)
          rest = substr(s, RSTART + RLENGTH)
          k = index(rest, run)
          if (k == 0) { out = out run; s = rest; continue }
          s = substr(rest, k + length(run))
        }
        return out s
      }
      FNR == 1 { flush(); cur = FILENAME; infence = 0; incode = 0; inlist = 0; prevblank = 1 }
      {
        text = $0
        sub(/\r$/, "", text)
        if (match(text, /^ ? ? ?(```|~~~)/)) {
          flush()
          incode = 0; prevblank = 0
          d = substr(text, RSTART + RLENGTH - 1, 1)
          if (!infence) { infence = 1; fc = d } else if (d == fc) infence = 0
          next
        }
        if (infence) next
        if (text ~ /^[ \t]*$/) { flush(); prevblank = 1; next }
        # An indented code block opens after a blank line outside a list and
        # runs until a less-indented line; an indented line that continues a
        # paragraph or a list item is prose.
        if (text ~ /^(    |\t)/) {
          if (incode || (prevblank && !inlist)) { incode = 1; prevblank = 0; next }
        } else {
          incode = 0
          if (text ~ /^ ? ? ?([-*+]|[0-9]+[.)])[ \t]/) inlist = 1
          else if (prevblank) inlist = 0
        }
        prevblank = 0
        low = tolower(text)
        blk = blk " " low
        low = strip_spans(low)
        gsub(/todo\(#[0-9]+\)/, "", low)
        if (low ~ ref) { hit[++nb] = FNR; hl[nb] = low }
      }
      END { flush() }
    ' "${agents[@]}" 2>/dev/null
  done
}

run_i6() {
  local file
  : >"$i6_tmp"
  for file in "${files[@]}"; do
    printf '@FILE\n%s\n' "$file" >>"$i6_tmp"
    LC_ALL=C awk \
    -v cue="^(${I6_CUE_ALT})_*([^[:alnum:]_]|\$)" \
    -v anycue="${WB_L}(${I6_CUE_ALT})${WB_R}" \
    -v paracue="(^|[^[:alnum:]_])_*(${I6_CUE_ALT})_*([^[:alnum:]_]|\$)" \
    -v paired="$I6_PAIRED_ERE" \
    -v rationale="$RATIONALE_ERE" \
    -v stopwords="$I6_CLAUSE_STOPWORDS" \
    -v transparent="$I6_CLAUSE_TRANSPARENT" '
    function flush(   low, len, i, start, ch, nx, s) {
      if (n == 0) return
      low = tolower(para)
      # Underscore counts as a boundary here so `_Never_` and `__Do not__`
      # emphasis reach the sentence gate; anycue keeps the raw count on the
      # boundaries of the per-line rule.
      if (low ~ paracue) {
        len = length(para); start = 1
        for (i = 1; i <= len; i++) {
          ch = substr(para, i, 1)
          if (ch == "." || ch == "!" || ch == "?") {
            nx = substr(para, i + 1, 1)
            if (nx == " " || nx == "\t") {
              judge(start, i)
              start = i + 1
            }
          }
        }
        if (start <= len) judge(start, len)
      }
      n = 0; para = ""
    }
    # A later clause (after "; ", ": ", ", ", an em or en dash, or " -- ")
    # that opens on a content word names what to do alongside the prohibition.
    # Stopwords open a continuation or consequence instead, transparent
    # adverbs are looked through, and a second prohibition is not an
    # alternative. Same closed lists as audit-noise noise-shapes.sh.
    function names_alternative(g,   body, nseg, segs, i, seg, first, rest) {
      body = g
      gsub(/\*\*|__/, "", body)
      gsub(/; |: |, |—|–| -- /, "\n", body)
      nseg = split(body, segs, "\n")
      for (i = 2; i <= nseg; i++) {
        seg = segs[i]
        while (seg ~ /^[ \t*_[]/) seg = substr(seg, 2)
        while (1) {
          match(seg, /^[a-z'"'"']*/)
          first = substr(seg, 1, RLENGTH)
          if (first == "") break
          rest = substr(seg, RLENGTH + 1)
          if (index(transparent, " " first " ") && rest ~ /^[ \t]/) {
            seg = rest
            sub(/^[ \t]+/, "", seg)
            continue
          }
          break
        }
        if (first == "") continue
        if (index(transparent, " " first " ")) continue
        if (index(stopwords, " " first " ")) continue
        if (seg ~ cue || seg ~ /^avoid([^[:alnum:]_]|$)/) continue
        return 1
      }
      return 0
    }
    function judge(from, to,   s, off, g, k, line) {
      s = substr(para, from, to - from + 1)
      off = from
      while (substr(s, 1, 1) == " " || substr(s, 1, 1) == "\t") { s = substr(s, 2); off++ }
      if (s == "") return
      g = tolower(s)
      gsub(/`/, "", g)
      while (match(g, /^([-*+]|[0-9]+[.)]|>|\[[ xX]\])[ \t]*/)) g = substr(g, RLENGTH + 1)
      while (match(g, /^(\*\*\*|\*\*|\*|___|__|_)/)) g = substr(g, RLENGTH + 1)
      if (g !~ cue) return
      if (g ~ paired) return
      if (names_alternative(g)) return
      if (index(g, "→") || index(g, "->")) return
      if (g ~ rationale) return
      line = lines[1]
      for (k = 1; k <= n; k++) if (starts[k] <= off) line = lines[k]
      # One row per line, however many prohibition sentences open on it.
      if (line in emitted) return
      emitted[line] = 1
      print "@HIT"
      print line
    }
    {
      text = $0
      sub(/\r$/, "", text)
      lowtext = tolower(text)
      if (lowtext ~ anycue && lowtext !~ rationale) raw++
    }
    NR == 1 && text ~ /^---[ \t]*$/ { infm = 1; next }
    infm { if (text ~ /^---[ \t]*$/) infm = 0; next }
    {
      # A fence may sit inside a blockquote. Per CommonMark it closes only on
      # the opener character, at least the opener length, with nothing but
      # whitespace after it; a fence line with an info string inside an open
      # fence is code.
      ft = text
      while (ft ~ /^ ? ? ?>/) sub(/^ ? ? ?> ?/, "", ft)
      if (match(ft, /^ ? ? ?(````*|~~~~*)/)) {
        d = substr(ft, RSTART, RLENGTH)
        rest = substr(ft, RSTART + RLENGTH)
        gsub(/ /, "", d)
        flush()
        if (!infence) { infence = 1; fc = substr(d, 1, 1); fl = length(d) }
        else if (substr(d, 1, 1) == fc && length(d) >= fl && rest ~ /^[ \t]*$/) infence = 0
        next
      }
      if (infence) next
      # A setext underline turns the pending paragraph into a heading, which
      # is never read. After a list item or blockquote, or with nothing
      # pending, the line is a thematic break or stray text: it only ends
      # the paragraph.
      if (text ~ /^ ? ? ?(==*|--*)[ \t]*$/) {
        if (n > 0 && first !~ /^[ \t]*([-*+]|[0-9]+[.)]|>)/) { n = 0; para = "" }
        else flush()
        next
      }
      if (text ~ /^[ \t]*$/ || text ~ /^[ \t]*\|/ || text ~ /\|[ \t]*$/ || text ~ /^[ \t]*#/ || text ~ /^[ \t]*<!--/) { flush(); next }
      if (text ~ /^[ \t]*([-*+]|[0-9]+[.)])[ \t]/) flush()
      if (n == 0) { para = text; first = text; n = 1; starts[1] = 1; lines[1] = NR }
      else { para = para " "; n++; starts[n] = length(para) + 1; lines[n] = NR; para = para text }
    }
    END { flush(); print "@RAW"; print (raw + 0) }
  ' "$file" >>"$i6_tmp"
  done
}

i6_summary() {
  awk '
    $0 == "@HIT" { surv++; next }
    $0 == "@RAW" { getline; raw += $0; next }
    END { printf "I6 raw=%d surviving=%d\n", raw + 0, surv + 0 }
  ' "$i6_tmp"
}

merge_report() {
  awk '
    $0 == "@SIDE" { getline; side = $0; next }
    side == "i6" && $0 == "@FILE" {
      getline
      i6_path[++i6n] = $0
      i6_count[i6n] = 0
      next
    }
    side == "i6" && $0 == "@HIT" {
      getline
      i6_hit[i6n, ++i6_count[i6n]] = $0
      next
    }
    side == "i6" && $0 == "@RAW" { getline; raw += $0; next }
    side == "other" && $0 == "@FILE" {
      getline
      o_path[++on] = $0
      o_count[on] = 0
      next
    }
    side == "other" {
      o_row[on, ++o_count[on]] = $0
      next
    }
    END {
      if (i6n != on) {
        print "instruction-scan: I6 and family groups diverged" > "/dev/stderr"
        exit 2
      }
      total = 0
      for (g = 1; g <= i6n; g++) {
        for (j = 1; j <= i6_count[g]; j++) {
          print i6_path[g] ":" i6_hit[g, j] ":I6"
          total++
        }
        for (j = 1; j <= o_count[g]; j++) {
          print o_row[g, j]
          total++
        }
      }
      if (total == 0) print "No instruction candidates found."
    }
  '
}

i6_tmp=$(mktemp)
other_tmp=$(mktemp)
trap 'rm -f "$i6_tmp" "$other_tmp"' EXIT

if [[ ${#files[@]} -eq 0 ]]; then
  case "$mode" in
    count) printf '0\n' ;;
    i6-counts) printf 'I6 raw=0 surviving=0\n' ;;
    *) printf 'No instruction candidates found.\n' ;;
  esac
  exit 0
fi

run_i6

if [[ "$mode" == "i6-counts" ]]; then
  i6_summary
  exit 0
fi

if [[ "$mode" == "count" ]]; then
  inner_mode=count
else
  inner_mode=merge
fi
{
  printf '\002%s\n' "${files[@]}"
  run_family 1 -nHiE "$I10_ERE"
  run_family 2 -nHiE "$I23_ERE"
  run_family 3 -nHiE "$I8_A_ERE"
  run_family 4 -nHiE "$I8_B_ERE"
  run_family 5 -nHiE "$I8_C_ERE"
  run_family 6 -nHiE "$I8_F_ERE"
  run_family 7 -nHiE "$I8_G_ERE"
  run_family 8 -nHiE "$I27_EFFORT_ERE"
  run_family 9 -nHE "$I28_A_ERE"
  run_family 10 -nHiE "$I28_B_ERE"
  run_family 11 -nHiE "$I25_ERE"
  run_family 12 -nHiE "$I38_ERE"
  run_i40 13
} | tr '\000' '\003' | awk -v mode="$inner_mode" -v body_only="$body_only" \
  -v ids="I10 I23 I8-a I8-b I8-c I8-f I8-g I27 I28-a I28-b I25 I38 I40" \
  -v brevity="$I27_BREVITY_ERE" "$SCAN_AWK" >"$other_tmp"

if [[ "$mode" == "count" ]]; then
  other=$(cat "$other_tmp")
  surv=$(awk '$0 == "@HIT" { n++ } END { print n + 0 }' "$i6_tmp")
  printf '%s\n' "$(( ${other:-0} + surv ))"
  exit 0
fi

{
  printf '@SIDE\ni6\n'
  cat "$i6_tmp"
  printf '@SIDE\nother\n'
  cat "$other_tmp"
} | merge_report
exit 0
