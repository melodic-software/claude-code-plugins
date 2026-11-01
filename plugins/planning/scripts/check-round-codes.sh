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
#                   (`scoped change (C3)`). `Checked against: C1, C3` is bare
#                   twice; each later use in the same block is not checked
#
# Lines inside fenced code blocks are ignored, in the ledger and the round; a
# fence left open exits 2.
#
# Exit 0 = no bare code (a round with none passes)
# Exit 1 = at least one bare code
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
}

die() {
  echo "error: $1" >&2
  exit 2
}

ledger=""
round=""
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
        used[c] = 1
        if (!named(line, pos, len)) {
          bare++
          printf "bare=%d:%s\n", lno, substr(line, pos, length(c))
        }
        break
      }
    }
  }
  FNR == 1 && NR > 1 && in_fence { exit 4 }
  FILENAME == ledger_file {
    sub(/\r$/, "")
    if (fence($0) || in_fence) next
    if ($0 ~ /^[ \t]*- [QCFS][0-9]+[ \t]*\|/) {
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
    sub(/\r$/, "")
    if (fence($0) || in_fence) next
    if (match($0, /^[^A-Za-z0-9]*Q[0-9]+[.):]/)) {
      c = substr($0, RSTART, RLENGTH)
      sub(/^[^A-Za-z0-9]*/, "", c)
      sub(/[.):]$/, "", c)
      add_code(c, 0)
    }
    next
  }
  {
    sub(/\r$/, "")
    if (fence($0) || in_fence) next
    if ($0 ~ /^[^A-Za-z0-9]*Q[0-9]+[.):]/) delete used
    grade($0, FNR)
  }
  END {
    if (in_fence) exit 4
    printf "codes=%d bare=%d status=%s\n", n_codes, bare, (bare ? "fail" : "ok")
    exit (bare ? 1 : 0)
  }
' ledger_file="$ledger" "$ledger" pass=1 "$round" pass=2 "$round"
status=$?
case $status in
0 | 1) exit "$status" ;;
4) die "unterminated fenced block (every line after it is hidden; close the fence)" ;;
*) die "could not grade: $round" ;;
esac
