#!/usr/bin/env bash
# Bare-code gate for a drafted /planning:interview round, run before the round is shown.
#
# A person reading a round has none of the session's legend. A ledger id
# (Q14, C3, F2, S1) or a session-shorthand term shown with nothing beside it
# makes them ask what it means before they can answer. This gate reads the
# ledger for every code and term, then flags each one whose first use in a
# question block carries no name.
#
#   code            a ledger row id (`- Q<N> |`, `- C<N> |`, `- F<N> |`,
#                   `- S<N> |`), a `Q<N>` that opens a question in the round,
#                   or a term in the ledger's `**Session shorthand:**` list
#                   (`- <term>: <definition>`; matched case-insensitively,
#                   with a plural `s` allowed)
#   question block  the lines from one `Q<N>` question line (any leading
#                   marker or markup, then `Q<N>` and `:`, `.` or `)`) to the
#                   next; the lines before the first are a block too
#   named           the use is followed by `:`, `(`, `,`, ` - ` or a dash and
#                   a word that is not itself a code nor, after a comma, a
#                   connective such as `so` or `and` (`C3: scoped change`,
#                   `question Q14, retry budget`, `lane (one builder
#                   session)`), or sits in parentheses after words
#                   (`scoped change (C3)`). The `Q<N>` that opens a question
#                   line is named by that question, whether `:`, `.` or `)`
#                   follows it. `Checked against: C1, C3` is bare twice; each
#                   later use in the same block is not checked
#   scenario id     a scenario walk's `S<N>` qualified by its question
#                   (`Q17.S1`) is not a ledger code and is skipped; a line
#                   opened by a bare `S<N>:` whose `S<N>` is a sweep row is
#                   bare, since a reader cannot tell the scenario from the row
#
# Lines inside fenced code blocks are ignored, in the ledger and the round; a
# fence left open exits 2.
#
# Exit 0 = no bare code and no structure failure (a round with none passes)
# Exit 1 = at least one bare code or structure failure
# Exit 2 = usage error, a missing or unreadable file, or an unterminated fence
#
# Usage:
#   bash check-round-codes.sh --ledger <interview-checklist.md> <round.md>
#   bash check-round-codes.sh --help
#
# Output (stdout, greppable): one `bare=<round line>:<code>` line per bare
# code, then a closing `codes=<n> bare=<n> status=<ok|fail>` line.

set -uo pipefail

usage() {
  sed -n '/^# Bare-code gate/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'TXT'

`--pacing round|single` (default round) names the round's question pacing.

Four structure checks run beside the bare-code check:

  answer line     each question block holds exactly one `My recommendation:`,
                  `Withheld:`, `Discovery:` or (the product action)
                  `Strong answer:` line
  scope check     the lines before the first question hold exactly one
                  `Scope check:` line

  ledger terms    each term in the ledger's `## Terminology matrix` table
                  (first column) that a question uses is also in that
                  question's own Context (from its `Context:` line to its
                  answer line); a use with no Context mention prints
                  `undefined=<question line>:<term>`
  single header   with `--pacing single`, the header holds only the round
                  title (`Round <N>`, as a heading or not), `Scope check:`,
                  `Later:`, `Held:` and `Settled by evidence:` lines; any
                  other line prints `extra=<line>:single-header`

A list item (`- Q4: ...`, `1. Q4: ...`) never opens a question.

A label may follow a marker (any run of characters outside printable ASCII,
such as an emoji) and sit in bold; round.py show reads labels the same way.
Each failure prints `missing=<line>:<what>` (`recommendation` or
`single-recommendation` at the question line, `scope-check` or
`single-scope-check` at line 1), and
the closing line gains ` structure=<n>`, which also counts the `undefined=`
and `extra=` lines.

Self-checks need judgment, so they print a `check=<line>:<name>` line and
never change the exit code:

  own-context-terms  at each question after the first
  flips-if-fact      at each `Flips if:` line
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
    [[ $# -ge 2 && ( "$2" == round || "$2" == single ) ]] || die "--pacing needs round or single"
    pacing="$2"
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

# The ledger is read once, the round twice: the first pass collects the round's
# own question ids, the second grades every line.
LC_ALL=C awk '
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
  function question_id(line,    c) {
    if (line ~ /^([ \t]*>)*[ \t]*([-*+]|[0-9]+[.)])[ \t]/) return ""
    if (!match(line, /^[^A-Za-z0-9]*Q[0-9]+[.):]/)) return ""
    c = substr(line, RSTART, RLENGTH)
    # Q17.S1 is a qualified scenario id, not a question line.
    if (c ~ /\.$/ && substr(line, RSTART + RLENGTH, 1) ~ /[A-Za-z0-9]/) return ""
    sub(/^[^A-Za-z0-9]*/, "", c)
    sub(/[.):]$/, "", c)
    return c
  }
  FNR == 1 && NR > 1 && in_fence { exit 4 }
  {
    sub(/\r$/, "")
    if (fence($0) || in_fence) next
  }
  FILENAME == ledger_file {
    if ($0 ~ /^#+[ \t]/) in_matrix = ($0 ~ /^##[ \t]+Terminology matrix[ \t]*$/)
    if (in_matrix && $0 ~ /^[ \t]*\|/) {
      t = $0
      sub(/^[ \t]*\|[ \t]*/, "", t)
      sub(/[ \t]*\|.*/, "", t)
      gsub(/[`*_]/, "", t)
      t = tolower(t)
      if (t != "" && t != "term" && t !~ /^[-: ]+$/ && !(t in seen_term)) {
        seen_term[t] = 1
        n_terms++
        term[n_terms] = t
      }
      next
    }
    if ($0 ~ /^[ \t]*- [QCFSP][0-9]+[ \t]*\|/) {
      c = $0
      sub(/^[ \t]*- /, "", c)
      sub(/[ \t]*\|.*/, "", c)
      add_code(c, 0)
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
    add_code(question_id($0), 0)
    next
  }
  function close_block() {
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
  }
  {
    if (!block_line && $0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Scope check(\*\*|__)?:/) has_scope++
    if (block_line && $0 ~ /^[^ -~]*[ \t]*(\*\*|__)?(My recommendation|Withheld|Discovery|Strong answer)(\*\*|__)?:/) block_answers++
  }
  {
    if ((c = question_id($0)) != "") {
      close_block()
      block_line = FNR
      block_answers = 0
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
      else if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?(My recommendation|Withheld|Discovery|Strong answer)(\*\*|__)?:/) in_ctx = 0
      hay = tolower($0)
      for (i = 1; i <= n_terms; i++) {
        if (has_term(hay, term[i])) {
          tused[i] = 1
          if (in_ctx) tctx[i] = 1
        }
      }
      if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?Flips if(\*\*|__)?:/) printf "check=%d:flips-if-fact\n", FNR
      if ($0 ~ /^[^ -~]*[ \t]*(\*\*|__)?My recommendation(\*\*|__)?:/) printf "check=%d:existing-control\n", FNR
    } else if (pacing == "single" && $0 !~ /^[ \t]*$/ && $0 !~ /^[^ -~]*[ \t]*((#+[ \t]+)?(\*\*|__)?Round[ \t]+[0-9]|(\*\*|__)?(Scope check|Later|Held|Settled by evidence)(\*\*|__)?:|---+[ \t]*$)/) {
      missing++
      printf "extra=%d:single-header\n", FNR
    }
    grade($0, FNR)
  }
  END {
    if (in_fence) exit 4
    close_block()
    if (pacing == "single") print "check=1:single-pacing"
    if (has_scope != 1) { missing++; print "missing=1:" (has_scope ? "single-scope-check" : "scope-check") }
    printf "codes=%d bare=%d status=%s structure=%d\n", n_codes, bare, ((bare || missing) ? "fail" : "ok"), missing
    exit ((bare || missing) ? 1 : 0)
  }
' ledger_file="$ledger" pacing="$pacing" "$ledger" pass=1 "$round" pass=2 "$round"
status=$?
case $status in
0 | 1) exit "$status" ;;
4) die "unterminated fenced block (every line after it is hidden; close the fence)" ;;
*) die "could not grade: $round" ;;
esac
