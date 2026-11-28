#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'TXT'
Bare-code gate for a drafted /planning:interview round: flags each ledger code or term first used with no name.

Usage: bash check-round-codes.sh --ledger <interview-checklist.md> [--pacing round|single] [--cap <n>] <round.md>
  --ledger  the interview ledger the codes and terms are read from
  --pacing  the round's question pacing (default round)
  --cap     the most questions the round may hold (the resolved questions_per_round, 1 or more)
  --help    print this help

Exit 0 no bare code and no structure failure; 1 at least one; 2 usage error, a missing or unreadable file, or an unterminated fence.

A person reading a round has none of the session's legend. A ledger id
(Q14, C3, F2, S1) or a session-shorthand term shown with nothing beside it
makes them ask what it means before they can answer. This gate reads the
ledger for every code and term, then flags each one whose first use in a
question block carries no name.

  code            a ledger row id (`- Q<N> |`, `- C<N> |`, `- F<N> |`,
                  `- S<N> |`), a `Q<N>` that opens a question in the round,
                  or a term in the ledger's `**Session shorthand:**` list
                  (`- <term>: <definition>`; matched case-insensitively,
                  with a plural `s` allowed)
  question block  the lines from one `Q<N>` question line (any leading
                  marker or markup, then `Q<N>` and `:`, `.`, `)` or
                  ` (<topic>):`) to the next; the lines before the first
                  are a block too
  named           the use is followed by `:`, `(`, `,`, ` - ` or a dash and
                  a word that is not itself a code nor, after a comma, a
                  connective such as `so` or `and` (`C3: scoped change`,
                  `question Q14, retry budget`, `lane (one builder
                  session)`), or sits in parentheses after words
                  (`scoped change (C3)`). The `Q<N>` that opens a question
                  line is named by that question, whether `:`, `.` or `)`
                  follows it. `Checked against: C1, C3` is bare twice; each
                  later use in the same block is not checked
  scenario id     a scenario walk's `S<N>` qualified by its question
                  (`Q17.S1`) is not a ledger code and is skipped; a line
                  opened by a bare `S<N>:` whose `S<N>` is a sweep row is
                  bare, since a reader cannot tell the scenario from the row

Lines inside fenced code blocks are ignored, in the ledger and the round; a
fence left open exits 2.

Output (stdout, greppable): one `bare=<round line>:<code>` line per bare
code, then a closing `codes=<n> bare=<n> status=<ok|fail>` line.

Structure checks run beside the bare-code check:

  answer line     each question block holds exactly one `My recommendation:`,
                  `Withheld:`, `Discovery:`, `No recommendation:` or (the
                  product action) `Strong answer:` line
  answer settles  a `No recommendation:` line is followed in its question by
                  a `Your answer settles:` line; else it prints
                  `missing=<no-recommendation line>:answer-settles`
  scope check     the lines before the first question hold exactly one
                  `Scope check:` line
  question cap    with `--cap <n>`, a round of more than n questions prints
                  `over-cap=<count>`
  ledger terms    each term in the ledger's `## Terminology matrix` table
                  (first column) or defined in another question's `Context:`
                  that a question uses is also in that question's own Context
                  (from its `Context:` line to its answer line); a use with
                  no Context mention prints `undefined=<question line>:<term>`
  basis and flip  each `My recommendation:` question carries a checkable basis
                  (a file:line, URL, user-stated fact, session tool check with
                  what it showed, or a sourced Context reference — never bare
                  `judgment`, a vague check such as `I checked` or `nothing
                  relevant`, a self-reference like `as established in Q2
                  above`, or a `(judgment)` Context line), failing with
                  `basis=<line>:missing` or `basis=<line>:uncheckable`; a
                  `Flips if:` or `Would change if:` line names a confirmable
                  condition (`flips-if=<line>:uncheckable`), and a Context
                  line naming an open/unknown fact on a recommended question
                  requires one (`missing=<line>:flips-if`)
  header          a header line shaped like a label (up to four words, then
                  `:`) other than `Scope check:`, `Wayfind:`, `Open:`,
                  `Next round:` (`Next round (over the cap of N):` too),
                  `Later:` and `Term:` prints `extra=<line>:header`, so a
                  `Held:` or `Settled by evidence:` line fails
  single header   with `--pacing single`, the header holds only the round
                  title (`Round <N>`, as a heading or not), one restate line
                  as the first non-blank line after it, and those allowed
                  label lines; any other line prints
                  `extra=<line>:single-header`. Each `Later:` topic must not
                  match another question title in the round or open in the
                  ledger (`preview=<line>:later:<Qid>`), and a shown
                  question's `Context:` or `Alternatives:` line must not
                  preview another question's title
                  (`preview=<line>:overlap:<Qid>`)

A list item (`- Q4: ...`, `1. Q4: ...`) never opens a question.

A label may follow a marker (any run of characters outside printable ASCII,
such as an emoji) and sit in bold; round.py show reads labels the same way.
Each failure prints `missing=<line>:<what>` (`recommendation` or
`single-recommendation` at the question line, `scope-check` or
`single-scope-check` at line 1, `flips-if` at the recommendation line), and
the closing line gains ` structure=<n>`, which also counts the `undefined=`,
`extra=`, `over-cap=`, `emphasis=`, `preview=`, `basis=` and `flips-if=`
lines.

Emphasis prints `emphasis=<line>` and fails the round: bold outside a
question line and an answer line, italics (`*x*`, `_x_`) and `~~`, inline
code skipped.

Self-checks need judgment, so they print a `check=<line>:<name>` line and
never change the exit code:

  own-context-terms  at each question after the first
  flips-if-fact      at each `Flips if:` line, a `- Flips if:` bullet included
  existing-control   at each `My recommendation:` line
  single-pacing      at line 1, with `--pacing single`
TXT
}

die() {
  echo "error: $1" >&2
  exit 2
}

ledger=""
round=""
pacing="round"
cap=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help | -h)
      usage
      exit 0
      ;;
    --ledger)
      [[ $# -ge 2 && -n "$2" ]] || die "--ledger needs a value"
      ledger="$2"
      shift 2
      ;;
    --pacing)
      [[ $# -ge 2 && ("$2" == round || "$2" == single) ]] || die "--pacing needs round or single"
      pacing="$2"
      shift 2
      ;;
    --cap)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || die "--cap needs a whole number, 1 or more"
      cap="$2"
      shift 2
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      [[ -z "$round" ]] || die "exactly one round file is expected"
      round="$1"
      shift
      ;;
  esac
done

[[ -n "$ledger" ]] || die "--ledger is required (see --help)"
[[ -n "$round" ]] || die "a round file is required (see --help)"
for f in "$ledger" "$round"; do
  [[ -f "$f" ]] || die "not a file: $f"
  [[ -r "$f" ]] || die "not readable: $f"
done
[[ "$ledger" != "$round" ]] || die "the round file and the ledger are the same file"

LC_ALL=C awk '
  BEGIN {
    sw_n = split("a about after again all also am an and another any are as at be because been before being between both but by can could did do does doing done down each else every few for from get gets give given go goes going good got had has have having he her here hers him his how if in into is it its just keep keeps kept know known last less let like long made make makes may me more most much must my need needs never new next no none nor not now of off often on once one only or other our out over own per put same say says see seen set shall she should since so some still such take takes than that the their them then there these they thing things think this those through time to too two under until up us use used uses very want wants was way we well were what when where whether which while who why will with within without would yet you your", sw_a, " ")
    for (sw_i = 1; sw_i <= sw_n; sw_i++) stop[sw_a[sw_i]] = 1
  }
  function fence(line,    f, bare) {
    if (!match(line, /^([ \t]*>)*[ \t]*(([-*+]|[0-9]+[.)])[ \t]+)?(```+|~~~+)/)) return 0
    f = substr(line, RSTART, RLENGTH)
    sub(/^[^`~]*/, "", f)
    bare = (substr(line, RSTART + RLENGTH) ~ /^[ \t]*$/)
    if (!in_fence) { in_fence = 1; fence_ch = substr(f, 1, 1); fence_len = length(f); return 1 }
    if (substr(f, 1, 1) == fence_ch && length(f) >= fence_len && bare) in_fence = 0
    return 1
  }
  function add_code(c, folded) {
    if (c == "" || c in seen_code) return
    seen_code[c] = 1
    n_codes++
    code[n_codes] = c
    fold[n_codes] = folded
  }
  function is_code(word,    i) {
    for (i = 1; i <= n_codes; i++) {
      if (fold[i] ? tolower(word) == code[i] : word == code[i]) return 1
    }
    return 0
  }
  function named(line, start, len,    before, after, rest, word) {
    before = substr(line, 1, start - 1)
    after = substr(line, start + len)
    sub(/^[`*_"]+/, "", after)
    if (match(after, /^[ \t]*(:|\(|,|[ \t]-|–|—)[ \t`*_"]*/)) {
      rest = substr(after, RLENGTH + 1)
      if (match(rest, /^[A-Za-z][A-Za-z0-9_]*/)) {
        word = substr(rest, 1, RLENGTH)
        if (after ~ /^[ \t]*,/ && tolower(word) ~ /^(and|or|but|so|then|which|that|since|because|while|as)$/) word = ""
        if (word != "" && !is_code(word)) return 1
      }
    }
    sub(/[`*_"]+$/, "", before)
    if (before ~ /[A-Za-z][^()]*\([ \t]*$/ && after ~ /^[ \t]*[),;]/) return 1
    return 0
  }
  function has_term(hay, t,    pos, off, len, prev, next1) {
    off = 0
    while ((pos = index(substr(hay, off + 1), t)) > 0) {
      pos += off
      len = length(t)
      prev = (pos > 1) ? substr(hay, pos - 1, 1) : ""
      next1 = substr(hay, pos + len, 1)
      if (next1 == "s" && substr(hay, pos + len + 1, 1) !~ /[a-z0-9_-]/) { len++; next1 = substr(hay, pos + len, 1) }
      off = pos + len - 1
      if (prev ~ /[a-z0-9_-]/ || next1 ~ /[a-z0-9_-]/) continue
      return 1
    }
    return 0
  }
  function grade(line, lno,    i, hay, c, pos, off, len, prev, next1, wordch) {
    for (i = 1; i <= n_codes; i++) {
      c = code[i]
      if (c in used) continue
      hay = fold[i] ? tolower(line) : line
      wordch = fold[i] ? "[A-Za-z0-9_-]" : "[A-Za-z0-9_]"
      off = 0
      while ((pos = index(substr(hay, off + 1), c)) > 0) {
        pos += off
        len = length(c)
        prev = (pos > 1) ? substr(hay, pos - 1, 1) : ""
        next1 = substr(hay, pos + len, 1)
        if (fold[i] && next1 == "s" && substr(hay, pos + len + 1, 1) !~ wordch) { len++; next1 = substr(hay, pos + len, 1) }
        off = pos + len - 1
        if (prev ~ wordch || next1 ~ wordch) continue
        if (prev == "." && substr(hay, 1, pos - 2) ~ /Q[0-9]+$/) continue
        used[c] = 1
        if ((c ~ /^S[0-9]+$/ && substr(line, 1, pos - 1) ~ /^[^A-Za-z0-9]*$/ && substr(line, pos + len) ~ /^[`*_"]*:/) || !named(line, pos, len)) {
          bare++
          printf "bare=%d:%s\n", lno, substr(line, pos, length(c))
        }
        break
      }
    }
  }
  # The id of the question a line opens, or "" when it opens none.
  function question_id(line,    c, rest) {
    if (line ~ /^([ \t]*>)*[ \t]*([-*+]|[0-9]+[.)])[ \t]/) return ""
    if (!match(line, /^[^A-Za-z0-9]*Q[0-9]+/)) return ""
    c = substr(line, RSTART, RLENGTH)
    rest = substr(line, RSTART + RLENGTH)
    if (rest !~ /^[.):]/ && rest !~ /^ \([^()]*\):/) return ""
    # Q17.S1 is a qualified scenario id, not a question line.
    if (rest ~ /^\./ && substr(rest, 2, 1) ~ /[A-Za-z0-9]/) return ""
    sub(/^[^A-Za-z0-9]*/, "", c)
    return c
  }
  # Bold is allowed only on a question title or an answer line (allow_bold);
  # italics and strikethrough nowhere. Inline code, path:line citations and
  # the quoted line of a Source block (exact text, kept as written) are skipped.
  function emphasis(line, lno, allow_bold,    t) {
    if (line ~ /^[ \t]*>/) return
    t = line
    gsub(/`[^`]*`/, "", t)
    gsub(/[^ \t()`]*[\/.][^ \t()`]*:[0-9][0-9,-]*/, "", t)
    if (!allow_bold && (t ~ /\*\*[^ *]/ || t ~ /(^|[^A-Za-z0-9_])__[^ _]/)) {
      missing++
      printf "emphasis=%d\n", lno
      return
    }
    gsub(/\*\*|__/, "", t)
    if (t ~ /(^|[^*A-Za-z0-9])\*[^ *]([^*]*[^ *])?\*([^*A-Za-z0-9]|$)/ ||
      t ~ /(^|[^A-Za-z0-9_])_[^ _]([^_]*[^ _])?_([^A-Za-z0-9_]|$)/ || t ~ /~~/) {
      missing++
      printf "emphasis=%d\n", lno
    }
  }
  function add_term(t) {
    gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (t == "" || (t in seen_term)) return
    seen_term[t] = 1
    n_terms++
    term[n_terms] = t
  }
  function stem_word(w) {
    w = tolower(w)
    if (length(w) > 4 && w ~ /ies$/) sub(/ies$/, "y", w)
    else if (length(w) > 4 && w ~ /ied$/) sub(/ied$/, "y", w)
    else if (length(w) > 5 && w ~ /ing$/) sub(/ing$/, "", w)
    else if (length(w) > 4 && w ~ /ed$/) sub(/ed$/, "", w)
    else if (length(w) > 3 && w ~ /s$/ && w !~ /(ss|us|is)$/) sub(/s$/, "", w)
    return w
  }
  function tokenize_into(text, out_arr,    s, n, parts, i, p, st, cnt) {
    delete out_arr
    s = tolower(text)
    gsub(/[^a-z0-9]+/, " ", s)
    n = split(s, parts, " ")
    cnt = 0
    for (i = 1; i <= n; i++) {
      p = parts[i]
      if (length(p) < 3 || p ~ /^[0-9]+$/ || (p in stop)) continue
      st = stem_word(p)
      if (length(st) < 3 || (st in stop)) continue
      if (!(st in out_arr)) {
        out_arr[st] = 1
        cnt++
      }
    }
    return cnt
  }
  function set_qtitle(qid, title_text, topic_text,    warr, k, w) {
    if (qid == "") return
    if (!(qid in seen_q)) {
      seen_q[qid] = 1
      n_q++
      q_list[n_q] = qid
    }
    if (title_text != "") q_raw_title[qid] = title_text
    if (topic_text != "") q_raw_topic[qid] = topic_text
  }
  function prep_qwords(    i, qid, full_t, warr, w, k) {
    if (qwords_ready) return
    qwords_ready = 1
    for (i = 1; i <= n_q; i++) {
      qid = q_list[i]
      full_t = q_raw_title[qid] " " q_raw_topic[qid]
      qw_cnt[qid] = tokenize_into(full_t, warr)
      k = 0
      for (w in warr) {
        qw[qid, w] = 1
        k++
        qw_item[qid, k] = w
      }
      qt_cnt[qid] = tokenize_into(q_raw_topic[qid], warr)
      for (w in warr) qt[qid, w] = 1
    }
  }
  function check_later_line(line, lno,    body, ni, items, k, iw, icnt, qi, oj, tot, dist, w) {
    body = line
    sub(/^[^:]*:/, "", body)
    ni = split(body, items, /[,;]/)
    for (k = 1; k <= ni; k++) {
      icnt = tokenize_into(items[k], iw)
      if (icnt == 0) continue
      for (qi = 1; qi <= n_q; qi++) {
        oj = q_list[qi]
        if (oj == first_round_q) continue
        tot = 0
        dist = 0
        for (w in iw) {
          if ((oj, w) in qw) {
            tot++
            if (first_round_q == "" || !((first_round_q, w) in qw)) dist++
          }
        }
        if (dist >= 1 && (tot >= 2 || dist * 2 >= icnt)) {
          missing++
          printf "preview=%d:later:%s\n", lno, oj
          break
        }
      }
    }
  }
  function check_single_overlap(line, lno, cur_q,    lw, lcnt, qi, oj, m, w, dj_size, tot, dist, ttot, tdist) {
    if (line ~ /^[^ -~]*[ \t]*(\*\*|__)?(Context|Alternatives)(\*\*|__)?:[ \t]*$/) return
    if (tolower(line) ~ /something else that would change/) return
    lcnt = tokenize_into(line, lw)
    if (lcnt == 0) return
    for (qi = 1; qi <= n_q; qi++) {
      oj = q_list[qi]
      if (oj == cur_q) continue
      if ((cur_q in round_q_ord) && (oj in round_q_ord) && round_q_ord[oj] <= round_q_ord[cur_q]) continue
      dj_size = 0
      for (m = 1; m <= qw_cnt[oj]; m++) {
        w = qw_item[oj, m]
        if (!((cur_q, w) in qw)) dj_size++
      }
      tot = 0
      dist = 0
      ttot = 0
      tdist = 0
      for (w in lw) {
        if ((oj, w) in qw) {
          tot++
          if (!((cur_q, w) in qw)) dist++
        }
        if ((oj, w) in qt) {
          ttot++
          if (!((cur_q, w) in qw)) tdist++
        }
      }
      if ((qt_cnt[oj] > 0 && tdist >= 1 && (ttot >= 2 || qt_cnt[oj] == 1)) ||
        dist >= 2 ||
        (dj_size == 1 && dist == 1 && tot >= 2)) {
        missing++
        printf "preview=%d:overlap:%s\n", lno, oj
        return
      }
    }
  }
  function extract_ctx_terms(line,    s, idx, left, right, t, nw, tw, low) {
    s = line
    sub(/^[ \t]*(([-*+]|[0-9]+[.)])[ \t]+)?/, "", s)
    if (s == "") return
    idx = index(s, ":")
    if (idx > 1) {
      left = substr(s, 1, idx - 1)
      right = substr(s, idx + 1)
      sub(/^[`*_]+/, "", right)
      if (right ~ /^[ \t]*[^ \t]/ && left !~ /[()\[\]\/.]/) {
        t = left
        gsub(/[`*_"]/, "", t)
        gsub(/^[ \t]+|[ \t]+$/, "", t)
        t = tolower(t)
        nw = split(t, tw, /[ \t]+/)
        if (nw >= 1 && nw <= 4 && length(t) >= 3 &&
          t !~ /^[qcfsp][0-9]+$/ && t !~ /^q[0-9]+\.s[0-9]+$/ &&
          t !~ /^(the|a|an|this|that|these|those|your|our|my|today|if|when|after|before|how|what|why|where|who)[ \t]/ &&
          t !~ /^(gap|note|example|today|upstream|current|problem|context|basis|why|gains|costs|evidence|flips if|origin|source|alternatives|my recommendation|recommendation|withheld|discovery|no recommendation|your answer settles|checked against|second view|departs from|commits you to|scope check|wayfind|open|later|term|summary|result|warning|caveat|tradeoff|trade-off|status|default|option|answer)$/) {
          add_term(t)
        }
      }
    }
    low = tolower(s)
    if (match(low, /^[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}[ \t]+means[ \t]+/)) {
      t = substr(low, 1, RLENGTH)
      sub(/[ \t]+means[ \t]+$/, "", t)
      sub(/^(a|an|the)[ \t]+/, "", t)
      if (length(t) >= 3 && t !~ /^(it|this|that|which|what|here|there|one|each|every|both|none|all|some|any|nothing|something)$/) {
        add_term(t)
      }
    }
    if (match(low, /^(a|an)[ \t]+[a-z][a-z0-9_-]*( [a-z][a-z0-9_-]*){0,2}[ \t]+is[ \t]+/)) {
      t = substr(low, 1, RLENGTH)
      sub(/^(a|an)[ \t]+/, "", t)
      sub(/[ \t]+is[ \t]+$/, "", t)
      if (length(t) >= 4 && t !~ /^(question|answer|decision|round|change|file|line|user|fact|option|choice|reason|reply|check|test|tool|rule|step|list|group|value|name|item|case|part|way|time|day|run|job|log|gap|bug|fix|issue|retry|store|queue|event|report|sender|receiver|reader|limit|window|error|alert|delay|burst|count|table|header|block|label|field|row|code|term|link|path|url|page|card|lane|mode|plan|spec|brief|task|work|note|doc|draft|scope|goal|bar|set)$/) {
        add_term(t)
      }
    }
  }
  function has_file_line(s) {
    if (s ~ /[A-Za-z0-9_.\/-]+\.[A-Za-z][A-Za-z0-9_]*:[0-9]/) return 1
    if (s ~ /[A-Za-z0-9._-]*[A-Za-z][A-Za-z0-9._-]*\/[A-Za-z0-9._\/-]*:[0-9]/) return 1
    if (s ~ /(^|[^A-Za-z0-9_])(README|LICENSE|CHANGELOG|NOTICE|CODEOWNERS|[A-Za-z]*file):[0-9]/) return 1
    return 0
  }
  function has_url(s) {
    return (s ~ /https?:\/\// || s ~ /\]\([^)]+\)/)
  }
  function has_user_source(low) {
    return (low ~ /(^|[^a-z])you[ \t]+(said|confirmed|quoted|stated|told|asked|set|chose|gave|specified|mentioned)([^a-z]|$)/ ||
      low ~ /(^|[^a-z])your[ \t]+(answer[ \t]+to[ \t]+q[0-9]|request|reply|message|published|partner[ \t]+terms|terms|spec|prompt)([^a-z]|$)/ ||
      low ~ /(^|[^a-z])user,[ \t]*round[ \t]+[0-9]/)
  }
  function is_uncheckable_basis(low,    s) {
    if (low ~ /(^|[^a-z])(nothing[ \t]+relevant|nothing[ \t]+found|nothing[ \t]+there|nothing[ \t]+useful)([^a-z]|$)/) return 1
    if (low ~ /(^|[^a-z])(as[ \t]+)?(established|shown|stated|decided|noted)[ \t]+in[ \t]+q[0-9]+([ \t]+above)?([^a-z]|$)/ && !has_user_source(low)) return 1
    if (low ~ /(^|[^a-z])(see|per|from|in)[ \t]+q[0-9]+[ \t]+above([^a-z]|$)/ && !has_user_source(low)) return 1
    s = low
    sub(/^[ \t]*(verified|documented|unverified)[,;: \t-]*/, "", s)
    gsub(/^[ \t]+|[ \t.]+$/, "", s)
    if (s ~ /^(i[ \t]+)?checked$/ || s ~ /^(bare[ \t]+)?(judgment|best[ \t]+practice|convention|rule[ \t]+of[ \t]+thumb)$/) return 1
    return 0
  }
  function has_tool_check_with_result(low) {
    if (low !~ /(^|[^a-z])(survey([ \t]+of|,)|glob[ \t]|grep[ \t]|git[ \t]+(log|status|diff|show|grep)|read[ \t]+of|command[ \t]|search[ \t]+for|scan[ \t]+of)([^a-z]|$)/ &&
      low !~ /(^|[^a-z])(glob|grep|survey|command|search)[ \t]+(for|returned|shows|showed|found)/) return 0
    return (low ~ /(^|[^a-z])(returned|shows|showed|found|no[ \t]+commits|no[ \t]+files|no[ \t]+application|no[ \t]+matches|no[ \t]+such|0[ \t]+|empty)([^a-z]|$)/ || low ~ /`[^`]+`/)
  }
  function record_ctx_paths(line,    rest, tok, base) {
    rest = line
    while (match(rest, /[A-Za-z0-9_.\/-]+\.[A-Za-z][A-Za-z0-9_]*:[0-9]/)) {
      tok = substr(rest, RSTART, RLENGTH)
      sub(/:[0-9]$/, "", tok)
      tok = tolower(tok)
      if (!(tok in seen_ctx_path)) {
        seen_ctx_path[tok] = 1
        ctx_paths[++n_ctx_paths] = tok
      }
      base = tok
      sub(/^.*\//, "", base)
      if (length(base) >= 5 && !(base in seen_ctx_path)) {
        seen_ctx_path[base] = 1
        ctx_paths[++n_ctx_paths] = base
      }
      rest = substr(rest, RSTART + RLENGTH)
    }
  }
  function is_ctx_line_sourced(line,    low) {
    low = tolower(line)
    if (low ~ /\([ \t]*(judgment|unverified|assumption|assumed|unconfirmed|guess|unknown|tbd)[ \t]*\)[ \t.]*$/ ||
      low ~ /(^|[^a-z])(judgment|unverified)[ \t.]*$/) return -1
    if (has_file_line(line) || has_url(line) || has_user_source(low) || has_tool_check_with_result(low)) return 1
    if (low ~ /\([ \t]*(survey|glob|grep|git[ \t]+[a-z]+|read|command|tool)[ \t]*,[ \t]*this[ \t]+session[ \t]*\)[ \t.]*$/) return 1
    return 0
  }
  function cites_sourced_context(s,    low, rest, seg, k, i, saw_sourced, saw_unsourced) {
    low = tolower(s)
    rest = low
    saw_sourced = 0
    saw_unsourced = 0
    while (match(rest, /(^|[^a-z0-9_])(context([ \t]+(lines?|items?))?[ \t]*#?|lines?[ \t]+#?)[0-9]+(([ \t]*,[ \t]*|[ \t]+and[ \t]+)#?[0-9]+)*/)) {
      seg = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      while (match(seg, /[0-9]+/)) {
        k = substr(seg, RSTART, RLENGTH) + 0
        seg = substr(seg, RSTART + RLENGTH)
        if (k in ctx_line_sourced) {
          if (ctx_line_sourced[k] == 1) saw_sourced = 1
          else if (ctx_line_sourced[k] == -1) saw_unsourced = 1
        }
      }
    }
    if (saw_sourced) return 1
    if (saw_unsourced) return -1
    for (i = 1; i <= n_ctx_paths; i++) {
      if (index(low, ctx_paths[i]) > 0) return 1
    }
    return 0
  }
  function has_checkable_basis(s,    low, cr) {
    low = tolower(s)
    if (is_uncheckable_basis(low)) return 0
    cr = cites_sourced_context(s)
    if (cr == -1) return 0
    if (cr == 1) return 1
    if (has_file_line(s) || has_url(s) || has_user_source(low) || has_tool_check_with_result(low)) return 1
    return 0
  }
  function is_uncheckable_flip(body,    s) {
    s = tolower(body)
    gsub(/^[ \t]+|[ \t.]+$/, "", s)
    if (s == "") return 1
    if (s ~ /^(things|requirements|circumstances|needs|priorities|plans|it|something)[ \t]+(change|changes|differ|differs)$/) return 1
    if (s ~ /^(if[ \t]+needed|if[ \t]+required|otherwise|you[ \t]+prefer[ \t]+otherwise|you[ \t]+disagree|it[ \t]+depends|tbd|none|n\/a|unknown|unclear|maybe|later|varies|depends)$/) return 1
    return 0
  }
  FNR == 1 && NR > 1 && in_fence { exit 4 }
  {
    sub(/\r$/, "")
    if (fence($0) || in_fence) next
  }
  FILENAME == ledger_file {
    if ($0 ~ /^#+[ \t]/) {
      in_matrix = ($0 ~ /^##[ \t]+Terminology matrix[ \t]*$/)
      in_register = ($0 ~ /^##[ \t]+Open-question register[ \t]*$/)
    }
    if (in_matrix && $0 ~ /^[ \t]*\|/) {
      t = $0
      sub(/^[ \t]*\|[ \t]*/, "", t)
      sub(/[ \t]*\|.*/, "", t)
      gsub(/[`*_]/, "", t)
      t = tolower(t)
      if (t != "" && t != "term" && t !~ /^[-: ]+$/) add_term(t)
      next
    }
    if ($0 ~ /^[ \t]*- [QCFSP][0-9]+[ \t]*\|/) {
      c = $0
      sub(/^[ \t]*- /, "", c)
      sub(/[ \t]*\|.*/, "", c)
      add_code(c, 0)
      if (in_register && c ~ /^Q[0-9]+$/) {
        nf = split($0, rcols, "|")
        if (nf >= 4) {
          rst = tolower(rcols[2])
          gsub(/^[ \t]+|[ \t]+$/, "", rst)
          rtitle = rcols[4]
          gsub(/^[ \t]+|[ \t]+$/, "", rtitle)
          if (rst == "open" && rtitle != "") set_qtitle(c, rtitle, "")
        }
      }
      in_gloss = 0
      next
    }
    if ($0 ~ /^\*\*Session shorthand:\*\*[ \t]*$/) { in_gloss = 1; next }
    if (in_gloss) {
      if ($0 ~ /^[ \t]*$/) next
      if ($0 !~ /^[ \t]*- [^:]+:/) { in_gloss = 0; next }
      t = $0
      sub(/^[ \t]*- /, "", t)
      sub(/:.*/, "", t)
      gsub(/[`*_]/, "", t)
      gsub(/^[ \t]+|[ \t]+$/, "", t)
      add_code(tolower(t), 1)
    }
    next
  }
  pass == 1 {
    p1_q = question_id($0)
    if (p1_q != "") {
      add_code(p1_q, 0)
      if (first_round_q == "") first_round_q = p1_q
      if (!(p1_q in round_q_ord)) round_q_ord[p1_q] = ++n_round_q
      p1_topic = ""
      p1_title = $0
      sub(/^[^A-Za-z0-9]*Q[0-9]+/, "", p1_title)
      if (match(p1_title, /^ \([^()]*\):/)) {
        p1_topic = substr(p1_title, 3, RLENGTH - 4)
        p1_title = substr(p1_title, RLENGTH + 1)
      } else {
        sub(/^[.):][ \t]*/, "", p1_title)
      }
      gsub(/[`*_]/, "", p1_title)
      gsub(/^[ \t]+|[ \t]+$/, "", p1_title)
      set_qtitle(p1_q, p1_title, p1_topic)
      p1_block = p1_q
      p1_in_ctx = 0
      next
    }
    if (p1_block != "") {
      if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Context(\*\*|__)?:/) {
        p1_in_ctx = 1
        p1_after = $0
        sub(/^[^:]*:/, "", p1_after)
        if (p1_after ~ /[^ \t]/) extract_ctx_terms(p1_after)
      } else if (is_answer($0)) {
        p1_in_ctx = 0
      } else if (p1_in_ctx) {
        extract_ctx_terms($0)
      }
    }
    next
  }
  function close_block(    i, combined) {
    if (!block_line) return
    if (block_answers != 1) {
      missing++
      printf "missing=%d:%s\n", block_line, (block_answers ? "single-recommendation" : "recommendation")
    }
    for (i = 1; i <= n_terms; i++) {
      if (tused[i] && !tctx[i]) {
        missing++
        printf "undefined=%d:%s\n", block_line, term[i]
      }
    }
    if (nr_line && !settles) {
      missing++
      printf "missing=%d:answer-settles\n", nr_line
    }
    if (rec_line) {
      if (basis_line || evid_line) {
        combined = basis_text " " evid_text
        if ((basis_line && is_uncheckable_basis(tolower(basis_text))) ||
          (evid_line && is_uncheckable_basis(tolower(evid_text))) ||
          !has_checkable_basis(combined)) {
          missing++
          printf "basis=%d:uncheckable\n", (basis_line ? basis_line : evid_line)
        }
      } else if (!has_checkable_basis(rec_text) && !ctx_has_source) {
        missing++
        printf "basis=%d:missing\n", rec_line
      }
      if (ctx_open_fact && !has_flips) {
        missing++
        printf "missing=%d:flips-if\n", rec_line
      }
    }
  }
  function is_answer(line) {
    return line ~ /^[^ -~]*[ \t]*(\*\*|__)?(My recommendation|Withheld|Discovery|Strong answer|No recommendation)(\*\*|__)?:/
  }
  function header_ok(line) {
    return line ~ /^[^ -~]*[ \t]*(\*\*|__)?(Scope check|Wayfind|Open|Next round( \([^)]*\))?|Later|Term)(\*\*|__)?:/
  }
  # A line shaped like a label: up to four words, the first capitalized, then `:`.
  function label_shaped(line) {
    return line ~ /^[^ -~]*[ \t]*(\*\*|__)?[A-Z][A-Za-z]*( [a-z]+)?( [a-z]+)?( [a-z]+)?( \([^)]*\))?(\*\*|__)?:([ \t]|$)/
  }
  {
    if (pacing == "single") prep_qwords()
    if (!block_line && $0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Scope check(\*\*|__)?:/) has_scope++
    if (block_line && is_answer($0)) block_answers++
  }
  {
    c = question_id($0)
    emphasis($0, FNR, c != "" || is_answer($0))
    if (c != "") {
      close_block()
      block_line = FNR
      block_id = c
      block_answers = 0
      nr_line = 0
      settles = 0
      rec_line = 0
      rec_text = ""
      basis_line = 0
      basis_text = ""
      evid_line = 0
      evid_text = ""
      has_flips = 0
      ctx_has_source = 0
      ctx_open_fact = 0
      in_alt = 0
      delete ctx_line_sourced
      delete ctx_paths
      delete seen_ctx_path
      n_ctx_paths = 0
      delete used
      # The Q<N> that opens a question line is the handle of that question,
      # named by the question itself whatever separator follows it.
      used[c] = 1
      delete tused
      delete tctx
      in_ctx = 0
      if (++n_blocks > 1) printf "check=%d:own-context-terms\n", FNR
    }
    if (block_line) {
      if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Context(\*\*|__)?:/) in_ctx = 1
      else if (is_answer($0)) in_ctx = 0
      if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Alternatives(\*\*|__)?:|([ \t]|^)Alternatives:/) in_alt = 1
      if (in_ctx) {
        ctx_body = $0
        if (ctx_body ~ /^[^ -~]*[ \t]*(\*\*|__)?Context(\*\*|__)?:/) sub(/^[^:]*:/, "", ctx_body)
        if (ctx_body ~ /[^ \t]/) {
          csrc = is_ctx_line_sourced(ctx_body)
          if (csrc == 1) {
            ctx_has_source = 1
            record_ctx_paths(ctx_body)
          }
          if (match(ctx_body, /^[ \t]*[0-9]+[.)][ \t]+/)) {
            ck = substr(ctx_body, 1, RLENGTH)
            gsub(/[^0-9]/, "", ck)
            ctx_line_sourced[ck + 0] = csrc
          }
          clow = tolower(ctx_body)
          if (clow ~ /(^|[^a-z])(not[ \t]+yet[ \t]+(known|verified|confirmed|measured|checked)|not[ \t]+known[ \t]+whether|unknown[ \t]+whether|unclear[ \t]+whether|unverified[ \t]+whether|uncertain[ \t]+whether|(has|have)[ \t]+not[ \t]+been[ \t]+(verified|confirmed|measured|checked)|do[ \t]+not[ \t]+know[ \t]+whether|don'\''t[ \t]+know[ \t]+whether|none[ \t]+of[ \t]+your[ \t]+answers[ \t]+so[ \t]+far[ \t]+says[ \t]+whether)([^a-z]|$)/) {
            ctx_open_fact = 1
          }
        }
      }
      if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?No recommendation(\*\*|__)?:/) { nr_line = FNR; settles = 0 }
      else if (nr_line && $0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Your answer settles(\*\*|__)?:/) settles = 1
      if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?My recommendation(\*\*|__)?:/) {
        rec_line = FNR
        rec_text = $0
        sub(/^[^:]*:/, "", rec_text)
        printf "check=%d:existing-control\n", FNR
      }
      if ($0 ~ /^([^ -~]*[ \t]*|[ \t]*[-*+][ \t]+)(\*\*|__)?Basis(\*\*|__)?:/) {
        if (!basis_line) basis_line = FNR
        bpart = $0
        sub(/^[^:]*:/, "", bpart)
        basis_text = basis_text " " bpart
      }
      if ($0 ~ /^([^ -~]*[ \t]*|[ \t]*[-*+][ \t]+)(\*\*|__)?Evidence(\*\*|__)?:/) {
        if (!evid_line) evid_line = FNR
        epart = $0
        sub(/^[^:]*:/, "", epart)
        evid_text = evid_text " " epart
      }
      if ($0 ~ /^([^ -~]*[ \t]*|[ \t]*[-*+][ \t]+)(\*\*|__)?(Flips if|Would change if)(\*\*|__)?:/) {
        has_flips = 1
        if ($0 ~ /^([^ -~]*[ \t]*|[ \t]*[-*+][ \t]+)(\*\*|__)?Flips if(\*\*|__)?:/) printf "check=%d:flips-if-fact\n", FNR
        fbody = $0
        sub(/^[^:]*:/, "", fbody)
        if (is_uncheckable_flip(fbody)) {
          missing++
          printf "flips-if=%d:uncheckable\n", FNR
        }
      }
      if (pacing == "single" && (in_ctx || in_alt)) {
        check_single_overlap($0, FNR, block_id)
      }
      hay = tolower($0)
      for (i = 1; i <= n_terms; i++) {
        if (has_term(hay, term[i])) {
          tused[i] = 1
          if (in_ctx) tctx[i] = 1
        }
      }
    } else if (pacing == "single" && $0 !~ /^[ \t]*$/) {
      if ($0 ~ /^[^ -~]*[ \t]*(#+[ \t]+)?(\*\*|__)?Round[ \t]+[0-9]/) restate_ok = 1
      else if (label_shaped($0) && !header_ok($0)) {
        missing++
        printf "extra=%d:single-header\n", FNR
      }
      else if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Term(\*\*|__)?:/) {}
      else if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Later(\*\*|__)?:/) {
        restate_ok = 0
        check_later_line($0, FNR)
      }
      else if (header_ok($0) || $0 ~ /^[^ -~]*[ \t]*---+[ \t]*$/) restate_ok = 0
      else if (restate_ok) restate_ok = 0
      else {
        missing++
        printf "extra=%d:single-header\n", FNR
      }
    } else if (label_shaped($0) && !header_ok($0)) {
      missing++
      printf "extra=%d:header\n", FNR
    }
    grade($0, FNR)
  }
  END {
    if (in_fence) exit 4
    close_block()
    if (cap && n_blocks > cap) {
      missing++
      printf "over-cap=%d\n", n_blocks
    }
    if (pacing == "single") print "check=1:single-pacing"
    if (has_scope != 1) { missing++; print "missing=1:" (has_scope ? "single-scope-check" : "scope-check") }
    printf "codes=%d bare=%d status=%s structure=%d\n", n_codes, bare, ((bare || missing) ? "fail" : "ok"), missing
    exit ((bare || missing) ? 1 : 0)
  }
' ledger_file="$ledger" pacing="$pacing" cap="$cap" "$ledger" pass=1 "$round" pass=2 "$round"
status=$?
case $status in
  0 | 1) exit "$status" ;;
  4) die "unterminated fenced block (every line after it is hidden; close the fence)" ;;
  *) die "could not grade: $round" ;;
esac
