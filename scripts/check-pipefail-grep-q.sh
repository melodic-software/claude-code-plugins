#!/usr/bin/env bash
# Gate: no shell file under scripts/ pipes into an early-exit grep.
#
#   scripts/check-pipefail-grep-q.sh              scan every scripts/**/*.sh
#   scripts/check-pipefail-grep-q.sh <file>...    scan exactly these files
#
# Flags `producer | grep` (also `|&`, egrep, fgrep, `\grep`, a path to grep, a
# `command`, `env`, `!` or `{` prefix, and a pipe split across lines) when that
# grep stops reading early: a short option cluster carrying q, l, L or m, or
# --quiet, --silent, --files-with-matches, --files-without-match, --max-count.
# Other wrappers (sudo, xargs) are not followed.
#
# Why: when grep exits at its first match, a producer still writing is killed
# by SIGPIPE, and under `set -o pipefail` the pipeline reports that 141 instead
# of grep's 0. A present match reads as absent, and a negated assertion passes.
# scripts/affected-tests.test.sh measured it on a 1 MB input (#4461). Sourced
# libraries are scanned too, since they run inside callers that set pipefail.
#
# The rewrite: match a variable with a here-string, `grep -q X <<<"$v"`, and a
# command's output with process substitution, `grep -q X < <(producer)`; the
# producer's status is then never read. `producer | grep X >/dev/null` is not a
# fix: GNU grep notices a /dev/null stdout and stops at the first match anyway.
#
# Detection is an inline awk lexer: quotes, $'...', backticks, $( ) and ${ }
# (also inside double quotes), escapes, comments and heredoc bodies are masked,
# `\`-newline continuations are joined, and what remains is searched for a
# single `|` whose next command word is grep. Each finding names the grep's line.
#
# Exit 0 clean, 1 findings, 2 environment or usage; findings on stderr. That is
# the whole family's contract, stated once in README.md, "The check-script
# contract", and held by scripts/check-script-contract.test.sh.

set -euo pipefail

if ! command -v awk >/dev/null 2>&1; then
  echo "check-pipefail-grep-q: awk is required but not installed" >&2
  exit 2
fi

files=()
if (($# == 0)); then
  cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
  while IFS= read -r f; do
    files+=("$f")
  done < <(find scripts -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
  if ((${#files[@]} == 0)); then
    echo "check-pipefail-grep-q: no shell files found under scripts/" >&2
    exit 2
  fi
else
  for f in "$@"; do
    if [[ ! -f "$f" || ! -r "$f" ]]; then
      echo "check-pipefail-grep-q: not a readable file: $f" >&2
      exit 2
    fi
    # awk reads an operand shaped like name=value as an assignment, not a file.
    [[ "$f" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && f="./$f"
    files+=("$f")
  done
fi

# shellcheck disable=SC2016  # awk program text; the shell must not expand it
LEXER='
function emit(ch) { o[++k] = ch; ol[k] = line }
function push(t, d) { ft[++sp] = t; fd[sp] = d }
function wordstart(p,   c) {
  if (p <= 1) return 1
  c = substr(S, p - 1, 1)
  return index(" \t\n;&|()", c) > 0
}
function heredoc_op(p,   j, ch, q, delim, dash) {
  emit("_"); emit("_")
  j = p + 2; dash = 0
  if (substr(S, j, 1) == "-") { dash = 1; emit("_"); j++ }
  while ((ch = substr(S, j, 1)) == " " || ch == "\t") { emit(" "); j++ }
  delim = ""
  while (j <= len) {
    ch = substr(S, j, 1)
    if (index(" \t\n;|&<>()", ch)) break
    if (ch == "\047" || ch == "\"") {
      q = ch; emit("_"); j++
      while (j <= len && (ch = substr(S, j, 1)) != q && ch != "\n") { delim = delim ch; emit("_"); j++ }
      if (ch == q) { emit("_"); j++ }
      continue
    }
    if (ch == "\\") { emit("_"); j++; ch = substr(S, j, 1) }
    delim = delim ch; emit("_"); j++
  }
  # A leading digit is a left shift (`(( 1 << 3 ))`, `a[1<<3]`), not a delimiter.
  if (delim != "" && delim !~ /^[0-9]/) { hd[++hn] = delim; hdash[hn] = dash }
  return j - 1
}
function heredoc_bodies(p,   h, e, body, cmp) {
  for (h = 1; h <= hn; h++) {
    while (p < len) {
      e = index(substr(S, p + 1), "\n")
      if (e == 0) { p = len; break }
      body = substr(S, p + 1, e - 1)
      p += e
      emit("\n"); line++
      cmp = body
      if (hdash[h]) sub(/^\t+/, "", cmp)
      if (cmp == hd[h]) break
    }
  }
  hn = 0
  return p
}
function subst_open(p,   n1, n2) {
  # p is at "$"; returns the index consumed through, or 0 when not an opener.
  n1 = substr(S, p + 1, 1); n2 = substr(S, p + 2, 1)
  if (n1 == "(" && n2 == "(") { push("A", 2); emit("_"); emit("_"); emit("_"); return p + 2 }
  if (n1 == "(") { push("C", 1); emit("$"); emit("("); return p + 1 }
  if (n1 == "{") { push("B", 1); emit("_"); emit("_"); return p + 1 }
  return 0
}
function lex(   i, c, t, nc, r) {
  k = 0; line = 1; sp = 0; hn = 0; incomment = 0
  push("C", 0)
  len = length(S)
  for (i = 1; i <= len; i++) {
    c = substr(S, i, 1); t = ft[sp]
    if (c == "\n") {
      emit("\n"); line++; incomment = 0
      if (hn > 0 && (t == "C" || t == "T")) i = heredoc_bodies(i)
      continue
    }
    if (incomment) { emit(" "); continue }
    if (t == "S") { emit("_"); if (c == "\047") sp--; continue }
    if (t == "E") {
      if (c == "\\") { emit("_"); i++; if (substr(S, i, 1) == "\n") { emit("\n"); line++ } else emit("_"); continue }
      emit("_"); if (c == "\047") sp--; continue
    }
    if (t == "A") {
      if (c == "(") fd[sp]++
      else if (c == ")") { fd[sp]--; if (fd[sp] <= 0) sp-- }
      emit("_"); continue
    }
    if (c == "\\") {
      nc = substr(S, i + 1, 1); i++
      if (nc == "\n") {
        if (t == "C" || t == "T") { emit(" "); emit(" ") } else { emit("_"); emit("\n") }
        line++
      } else if ((t == "C" || t == "T") && nc ~ /[A-Za-z0-9_]/) {
        # `\grep` bypasses an alias and still runs grep; keep the word readable.
        emit("\\"); emit(nc)
      } else { emit("_"); emit("_") }
      continue
    }
    if (t == "D" || t == "B") {
      if (c == "$" && (r = subst_open(i))) { i = r; continue }
      if (c == "`") { push("T", 0); emit("_"); continue }
      if (t == "D" && c == "\"") { sp--; emit("_"); continue }
      if (t == "B") {
        if (c == "}") { sp--; emit("_"); continue }
        if (c == "\"") { push("D", 0); emit("_"); continue }
        if (c == "\047" && ft[sp - 1] != "D") { push("S", 0); emit("_"); continue }
      }
      emit("_"); continue
    }
    # code: the top level, $( ), or backticks
    if (t == "T" && c == "`") { sp--; emit("_"); continue }
    if (c == "#" && wordstart(i)) { incomment = 1; emit(" "); continue }
    if (c == "\047") { push("S", 0); emit("_"); continue }
    if (c == "\"") { push("D", 0); emit("_"); continue }
    if (c == "`") { push("T", 0); emit("_"); continue }
    if (c == "$") {
      nc = substr(S, i + 1, 1)
      if (nc == "\047") { push("E", 0); emit("_"); emit("_"); i++; continue }
      if (nc == "\"") { push("D", 0); emit("_"); emit("_"); i++; continue }
      if ((r = subst_open(i))) { i = r; continue }
      emit("$"); continue
    }
    if (c == "(") { fd[sp]++; emit(c); continue }
    if (c == ")") {
      emit(c)
      if (fd[sp] > 0) fd[sp]--
      if (sp > 1 && t == "C" && fd[sp] == 0) sp--
      continue
    }
    if (c == "<" && substr(S, i + 1, 1) == "<") {
      if (substr(S, i + 2, 1) == "<") { emit("_"); emit("_"); emit("_"); i += 2; continue }
      i = heredoc_op(i); continue
    }
    emit(c)
  }
}
function skipws(y, nl) {
  while (y <= k && (o[y] == " " || o[y] == "\t" || (nl && o[y] == "\n"))) y++
  return y
}
function readword(y) {
  W = ""
  while (y <= k && index(" \t\n;|&()", o[y]) == 0) { W = W o[y]; y++ }
  return y
}
function early_exit(z,   w, ch, ci, name) {
  # z is just past the grep word; parse its arguments up to the command end.
  while (1) {
    z = skipws(z, 0)
    if (z > k || index("\n;|&)", o[z])) return 0
    z = readword(z); w = W
    if (w == "") { z++; continue }
    if (w == "--") return 0
    if (substr(w, 1, 2) == "--") {
      name = w; sub(/=.*/, "", name)
      if (name ~ /^--(quiet|silent|files-with-matches|files-without-match|max-count)$/) return 1
      if (w !~ /=/ && name ~ /^--(regexp|file|after-context|before-context|context|devices|directories|label|include|exclude|exclude-dir|exclude-from|group-separator|binary-files)$/) {
        z = skipws(z, 0); z = readword(z)
      }
      continue
    }
    if (substr(w, 1, 1) == "-" && length(w) > 1) {
      for (ci = 2; ci <= length(w); ci++) {
        ch = substr(w, ci, 1)
        if (index("qlLm", ch)) return 1
        if (index("efABCdD", ch)) {
          if (ci == length(w)) { z = skipws(z, 0); z = readword(z) }
          break
        }
      }
    }
  }
}
function scan(file,   x, y, y2, w, gl, text) {
  lex()
  for (x = 1; x <= k; x++) {
    if (o[x] != "|") continue
    if (x > 1 && (o[x - 1] == "|" || o[x - 1] == ">")) continue
    if (x < k && o[x + 1] == "|") continue
    y = x + 1
    if (o[y] == "&") y++
    y = skipws(y, 1)
    # Skip what may stand before the command name: assignments, a wrapper, its
    # options, a negation, a brace group or subshell.
    for (;;) {
      gl = ol[y]; y2 = readword(y); w = W
      if (w == "" && o[y] == "(") { y = skipws(y + 1, 1); continue }
      if (w !~ /^([A-Za-z_][A-Za-z0-9_]*=|-)/ && w != "command" && w != "env" && w != "!" && w != "{") break
      y = skipws(y2, 0)
    }
    sub(/^\\/, "", w); sub(/^.*\//, "", w)
    if (w != "grep" && w != "egrep" && w != "fgrep") continue
    if (!early_exit(y2)) continue
    text = L[gl]; sub(/^[ \t]+/, "", text); sub(/[ \t]+$/, "", text)
    printf "PIPED EARLY-EXIT GREP: %s:%d: %s\n", file, gl, text
  }
}
function finish(   li) {
  S = ""
  for (li = 1; li <= n; li++) S = S L[li] "\n"
  scan(cur)
}
FNR == 1 {
  if (NR > 1 && n > 0) finish()
  n = 0; cur = FILENAME
}
{ sub(/\r$/, ""); L[++n] = $0 }
END { if (n > 0) finish() }
'

findings="$(LC_ALL=C awk "$LEXER" "${files[@]}")" || {
  echo "check-pipefail-grep-q: awk failed while scanning" >&2
  exit 2
}

if [[ -z "$findings" ]]; then
  echo "No piped early-exit grep in ${#files[@]} shell file(s)."
  exit 0
fi

printf '%s\n' "$findings" >&2
count="$(grep -c '' <<<"$findings")"
echo "$count piped early-exit grep(s) found; rewrite each as grep ... <<<\"\$v\" or grep ... < <(producer)." >&2
exit 1
