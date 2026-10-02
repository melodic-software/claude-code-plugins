#!/usr/bin/env bash
# instruction-scan.sh — advisory deterministic pre-scan for the audit-instructions
# skill. Marks CANDIDATE lines for catalog checks (reference/criteria.md) in the
# instruction files handed to it:
#
#   I6  imperative bare prohibition: a SENTENCE that opens with "never", "do
#       not", "don't", "must not", or "should not" (after list, blockquote,
#       checkbox, and emphasis markers), carries no paired positive ("instead",
#       "rather than", "prefer", "in place of", "in favor of"), and carries no
#       rationale marker (because/since/so that/…). Soft-wrapped paragraph lines
#       are accumulated into one text before sentences are split, and a row is
#       attributed to the first physical line of its sentence. Frontmatter,
#       fenced code, table rows, headings, and HTML comment lines are never
#       read. These are the gates docs-hygiene's audit-noise
#       rule-negation-without-positive measures, less its hard-guardrail
#       carve-out (secrets, credentials, production, …): a guardrail "never"
#       still owes I6's fallback rationale (I7), so it stays a candidate.
#       The gates are structural, not the catalog's fences, which the model
#       lane still applies to every row.
#       --i6-counts reports the raw count (the per-line rule: a prohibition
#       token on a line with no rationale marker) beside the surviving count.
#   I10 reasoning-echo directive (show/explain/reproduce your thinking or
#       reasoning, "think out loud", reasoning_extraction). These tell the model
#       to emit its internal reasoning as response text.
#   I8  model-era candidates, four pattern families emitted with per-family ids
#       matching the catalog's I8 rows — I8-a and I8-c are Opus-5-scoped, I8-b is
#       unscoped (promotion gate met; fires for every target). The scanner is
#       model-blind — the model lane adjudicates against the resolved target model
#       and the criteria-owned fences:
#         I8-a instructed self-check ("double-check", "re-verify", "final
#              verification step", "use a subagent to verify", "verify your own work")
#         I8-b conservative-reporting directives ("be conservative", "only report
#              high-severity", "don't nitpick")
#         I8-c don't-think / don't-reason directives ("do not think", "don't
#              reason", "without thinking", "skip the reasoning")
#         I8-f think-carefully steers ("think carefully", "think step by step",
#              "ultrathink"); Opus-5.5-scoped
#       Over-production is by design: restraint clauses, quoted/meta text,
#       idiomatic uses ("do not think of this as…"), and substring near-misses
#       ("don't reasonably…") ARE emitted; the fences live in
#       reference/criteria.md, never here.
#   I23 self-estimated context-budget trigger ("context is heavy", "running low
#       on context", "remaining context", "check /context", "final third of the
#       window"). The catalog's subject is a directive to judge one's own window
#       and then stop, summarize, hand off, or trim on that basis — but the
#       scanner marks the BUDGET PHRASING alone and never the verb it governs,
#       because the two routinely sit in different sentences. It therefore also
#       emits the counter-steer text that forbids the behavior (inverted
#       polarity), documents ABOUT the pattern, and operator-facing budgets:
#       all three are criteria-owned exemptions the model lane applies.
#   I27 effort-for-brevity candidates: a line pairing an effort-lowering
#       directive ("lower/reduce/decrease/drop … effort") with a brevity token
#       (short/brief/concise/terse/length/verbose/wordy). The model lane
#       adjudicates whether the line actually premises brevity on effort.
#   I28 trigger-emphasis / blanket-default candidates, two families:
#         I28-a forced-compliance emphasis ("CRITICAL:", "You MUST", "MANDATORY";
#              case-sensitive — the all-caps marker is the signal)
#         I28-b blanket tool defaults ("default to using", "if in doubt, use")
#   I25 retired sampling parameters (temperature/top_p/top_k prescriptions; the
#       affected-model range is a criteria-owned Detect condition)
#
# Advisory: prints candidate rows, ALWAYS exits 0 (candidates never fail a run).
# Requires grep, tr, and awk; exits 2 when one is absent.
#
# Rows are `file:line:check-id` (grep -n convention). An I6 row is a sentence
# that opens on a prohibition and survives the paired-positive and rationale
# gates; a line may surface once per matching check
# id (I6, I10, I23, I27, and one of the I8 families). Nonexistent path
# arguments are skipped, not errors.
#
# --body-only skips YAML frontmatter (a leading `---` block), so no row can point
# at a `description`, `when_to_use`, or any trigger phrase quoted in one. This is
# the fence the findings-relay path requires: check-skill.sh check 3 hard-FAILs a
# dropped `'trigger phrase'` versus the base ref, so a remediation that edits a
# description is an auto-invocation regression. It is OPT-IN rather than the
# default because the human-facing audit legitimately reports on frontmatter
# content (a stale harness claim in a description is a real finding) — what must
# never happen is such a row reaching an APPLY relay. Callers that persist
# findings pass it; the report path does not.
#
# Usage:
#   instruction-scan.sh FILE...            # one candidate row per line; exit 0
#   instruction-scan.sh --count FILE...    # integer candidate count only; exit 0
#   instruction-scan.sh --body-only FILE...  # skip YAML frontmatter; exit 0
#   instruction-scan.sh --i6-counts FILE...  # `I6 raw=<n> surviving=<n>`; exit 0
#   instruction-scan.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
instruction-scan.sh — mark I6/I8/I10/I23/I25/I27/I28 instruction candidates in given files.

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
don't-reason, I8-f think-carefully steer. I23 marks self-estimated context-budget phrasing. I27 marks
effort-for-brevity candidates (effort-lowering directive paired with a brevity
token on one line). I28 families: I28-a forced-compliance emphasis
(case-sensitive), I28-b blanket tool defaults. I25: retired sampling
parameters.

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

if ! command -v grep >/dev/null 2>&1; then
  echo "ERROR: grep required" >&2
  exit 2
fi
for tool in tr awk; do
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

# --- Detection patterns (case-insensitive) -----------------------------------
# POSIX ERE has no word-boundary assertion (GNU grep's ERE \b is an extension
# BSD grep lacks), so compose boundaries from consuming byte classes — safe here
# because every use is line-level -q/-n matching, never match extraction. The
# negated classes are single-byte under a C locale, which still bounds correctly
# against multibyte neighbors: their first byte is non-alnum.
WB_L="(^|[^[:alnum:]_])"
WB_R='([^[:alnum:]_]|$)'
# Rationale markers: a prohibition sentence carrying one of these is not an I6
# candidate.
RATIONALE_ERE="because|${WB_L}since${WB_R}|${WB_L}so that${WB_R}|${WB_L}so it${WB_R}|${WB_L}so the${WB_R}|${WB_L}to avoid${WB_R}|${WB_L}otherwise${WB_R}|${WB_L}in order to${WB_R}|${WB_L}rationale${WB_R}|${WB_L}reason${WB_R}"
# I6's sentence-level gates. Lowercase spellings throughout: the awk program
# folds each sentence to lowercase before testing it, so `do NOT` reads as
# `do not`. The ('|’)? alternation covers straight, curly (U+2019), and absent
# apostrophes as literal byte sequences; a `.` or bracket class breaks on the
# multibyte apostrophe under a C locale.
I6_CUE_ALT="never|do not|don('|’)?t|must ?not|mustn('|’)?t|should ?not|shouldn('|’)?t"
I6_PAIRED_ERE="${WB_L}(instead|rather than|prefer(s|red|ring)?|in place of|in favou?r of)${WB_R}"
I6_CLAUSE_STOPWORDS=" the a an and or but nor so yet if unless until when while where which who whose that this these those it its they their them we our us you your he she his her i is are was were be been being as at by for from in into of on onto to with without not no never nor don't do does did doing ever even because since though although however therefore thus hence per via plus minus other others such same both all any each every more most less least than there here what how why "
I6_CLAUSE_TRANSPARENT=" just simply always then also still only first next now again finally "
# I10 reasoning-echo phrasing.
I10_ERE="(show|explain|reproduce|echo|transcribe|verbalize|narrate|share|describe) (your |the )?(thinking|reasoning|thought process|chain of thought)"
I10_ERE="${I10_ERE}|think out loud|walk (me|us) through your (thinking|reasoning)|reasoning_extraction|chain[- ]of[- ]thought"
# I8 model-era candidate families (I8-a/I8-c Opus-5-scoped, I8-b unscoped;
# scanner is model-blind; per-family ids I8-a/I8-b/I8-c). Stem forms
# (`re[- ]?verif`) deliberately catch inflections; over-production is the contract.
I8_A_ERE="double[- ]check|${WB_L}re[- ]?verif|final verification step|(sub)?agent to verify|have (a |an )?(sub)?agent verify|verifier (sub)?agent|verify your (own )?work"
I8_B_ERE="be conservative|(only report|report only) (the )?(high|critical)|(don('|’)?t|do not) nitpick"
I8_C_ERE="(do not|don('|’)?t) (think|reason)|without thinking|skip the reasoning"
I8_F_ERE="think (very |really )?(carefully|hard|harder|deeply|thoroughly|step[- ]by[- ]step)|${WB_L}ultrathink${WB_R}"
# I23 self-estimated context-budget phrasing. Deliberately anchored to
# BUDGET-AS-TRIGGER forms, never to the bare term "context window" — that term
# is ordinary vocabulary in any instruction surface discussing sessions, and
# matching it would return the whole corpus rather than a candidate set.
I23_ERE="context (is |gets |getting |grows )?(heavy|tight|saturated|exhausted)|heavy context"
I23_ERE="${I23_ERE}|(running|runs|run) (out of|low on) context|low on context"
I23_ERE="${I23_ERE}|remaining[- ](context|window|tokens)|context[- ](budget|percentage|occupancy|countdown)|token[- ](budget|countdown)"
I23_ERE="${I23_ERE}|(check|checking|watch|watching|monitor|monitoring) (the |your )?/context|/context output"
I23_ERE="${I23_ERE}|(final|last) (third|quarter|half) of (the|your|its) window|window position"
I23_ERE="${I23_ERE}|(nearing|approaching) (the )?(context|token)[- ](limit|cap|budget|window)"
# I27 effort-for-brevity: both patterns must hit the SAME line — the AND lives
# in scan_file. Stem forms catch inflections (decrease/decreasing via the bare
# stem, drop/dropped/dropping via the doubled-p form; verbos carries no left
# boundary so compounds match too); over-production is the contract, as with I8.
I27_EFFORT_ERE="(lower|reduc|decreas|dropp?)(e|ed|es|ing|s)? (the |your )?effort" # spellchecker:disable-line
I27_BREVITY_ERE="${WB_L}short|${WB_L}brief|${WB_L}concise|${WB_L}terse|${WB_L}length|verbos|${WB_L}wordy"
# I28 trigger-emphasis / blanket-default candidates (criteria fences decide:
# emphasis guarding a destructive gate or a stated hard precondition is not a
# finding). Case-sensitive arm: the all-caps markers themselves. "use even
# when" is an attested blanket-default form ("Use even when you think you know
# the answer"), not a quoted guide example — over-production by design.
I28_A_ERE="CRITICAL:|IMPORTANT:|(You|you) MUST|MANDATORY|ALWAYS use|NEVER skip"
I28_B_ERE="${WB_L}default to (using|running|calling)${WB_R}|if in doubt,? use|${WB_L}always use${WB_R}|use even when"
# I25 retired sampling parameters (model range is a criteria-owned Detect
# condition; the scanner is model-blind and marks every prescription).
I25_ERE="${WB_L}temperature${WB_R}|${WB_L}top_p${WB_R}|${WB_L}top_k${WB_R}"

# --- Scan ---------------------------------------------------------------------
# Each family runs ONE grep over every file (per argv chunk), so the process
# count is a fixed number per run rather than per file or per hit: the group
# subshell, one grep per family per chunk, one tr, and one awk. The awk regroups
# the rows into argument order, then family order, then line order, which is
# the order a per-file scan produces.
#
# grep --null ends each file name with a NUL so a path containing a colon (C:/...)
# splits unambiguously; tr maps the NUL to \003 because not every awk reads NUL
# bytes. The awk applies I27's same-line filter to the line TEXT alone:
# a hit is kept only when a brevity token shares its line. The filter pattern
# is lowercase, so matching it against tolower(text) is the case fold grep -i
# gives. I6 is not one of these greps. Its sentence gates run as one awk per
# file, and the two streams merge back into argument order, then family order.

# frontmatter_end (awk function in SCAN_AWK)
#
# The line number of a leading YAML frontmatter block's CLOSING `---`, or 0
# when the file has none. Frontmatter is recognized only when `---` is the very
# first line, which is the form every skill, agent, and output-style surface
# uses; a `---` thematic break mid-document therefore opens nothing. An UNCLOSED
# leading `---` returns the file's line count, fencing the whole file rather than
# none of it — the fail-safe direction, since the alternative would route a
# malformed-frontmatter description straight to an apply relay.
#
# BOTH comparisons use `^---[[:space:]]*$`, deliberately identical to this repo's
# authoritative extractor `skill_frontmatter::extract`
# (plugins/skill-quality/scripts/skill-frontmatter.sh) — what `check-skill.sh`, the
# hard-FAIL gate this fence exists to satisfy, actually parses frontmatter with.
# Exact equality against `---` is STRICTER than that parser, and the mismatch runs
# the dangerous way: a delimiter carrying trailing whitespace or a CR is real
# frontmatter to the gate but invisible here, so the block would be read as body
# and the description and when_to_use lines would become emittable candidates —
# the fence silently inverted on exactly the Windows-authored and
# hand-edited files it most needs to hold for. Measured, not theorized: before
# this, a CRLF fixture produced rows at lines 2 and 3. `[[:space:]]` covers CR.
#
# Under --body-only the awk drops every hit at or above that line, so no emitted
# row can carry a remediation that edits a description, when_to_use, or a
# trigger phrase quoted in one. It reads a file's frontmatter only when that
# file has a hit, and never forks to do it.
#
# A grep "Binary file X matches" notice (no NUL) is kept as a row with the text
# before its first colon as the line field, which is what a per-file read of
# grep -n output makes of it.
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
  else if (mode != "merge" && total == 0) print "No instruction candidates found."
}'

# Existing files in argument order, duplicates kept: each occurrence re-emits
# its rows, and a nonexistent path is skipped.
files=()
for file in "$@"; do
  [[ -f "$file" ]] && files+=("$file")
done

# Chunk the file list so no single grep command line nears the 32,767-character
# Windows limit.
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

# run_family <index> <grep-flags> <ere>
#
# The grep flags travel per family because I28-a is case-SENSITIVE by design
# (the all-caps marker IS the signal) while every other family folds case.
run_family() {
  local idx="$1" flags="$2" ere="$3" c
  printf '\001%s\n' "$idx"
  for ((c = 0; c < ${#chunk_start[@]}; c++)); do
    grep "$flags" --null -e "$ere" -- "${files[@]:chunk_start[c]:chunk_len[c]}" 2>/dev/null
  done
}


# I6 sentence scan, one awk per file. A file with no lines still gets a group
# marker so the merge stays aligned with the batched families.
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
  if [[ ${#files[@]} -gt 0 ]]; then
    printf '\002%s\n' "${files[@]}"
  fi
  if [[ ${#chunk_start[@]} -gt 0 ]]; then
    run_family 1 -nHiE "$I10_ERE"
    run_family 2 -nHiE "$I23_ERE"
    run_family 3 -nHiE "$I8_A_ERE"
    run_family 4 -nHiE "$I8_B_ERE"
    run_family 5 -nHiE "$I8_C_ERE"
    run_family 6 -nHiE "$I8_F_ERE"
    run_family 7 -nHiE "$I27_EFFORT_ERE"
    run_family 8 -nHE "$I28_A_ERE"
    run_family 9 -nHiE "$I28_B_ERE"
    run_family 10 -nHiE "$I25_ERE"
  fi
} | tr '\000' '\003' | awk -v mode="$inner_mode" -v body_only="$body_only" \
  -v ids="I10 I23 I8-a I8-b I8-c I8-f I27 I28-a I28-b I25" \
  -v rationale="$RATIONALE_ERE" -v brevity="$I27_BREVITY_ERE" "$SCAN_AWK" >"$other_tmp"

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
