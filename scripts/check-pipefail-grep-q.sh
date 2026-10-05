#!/usr/bin/env bash
# Gate: no shell file in the repository pipes into an early-exit grep.
#
#   scripts/check-pipefail-grep-q.sh              scan every *.sh git lists
#                                                 (tracked, or untracked and
#                                                 not ignored)
#   scripts/check-pipefail-grep-q.sh <file>...    scan exactly these files
#
# The default scan skips the findings of each file listed in
# scripts/pipefail-grep-q-baseline.txt, the known offenders. The baseline is a
# ratchet: an entry whose file is gone or no longer offends is a finding, so
# the list only shrinks. It exempts whole files, so a new pipe added to a
# listed file is not caught. Never add a file to it: rewrite the pipe instead.
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
# scripts/affected-tests.test.sh measured it on a 1 MB input (#4461). Small
# input is not safe either: bash line-buffers its stdout, so `printf '%s\n' "$v"`
# writes one line at a time, and a grep that matched an early line can exit
# before the rest is written. Sourced libraries are scanned too, since they run
# inside callers that set pipefail.
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
# Options are read with their quoting removed, so `grep "-q" x` counts as -q.
#
# Known gap: the lexer does not model `case`, so a pattern-ending `)` inside a
# `$( )` closes that frame early. Inside double quotes the rest of the
# substitution is then masked as quoted text, and a pipe there is missed:
#   v="$(case $y in a) echo a;; esac | grep -q x)"
# scripts/check-pipefail-grep-q.test.sh pins this as a known gap.
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
baseline=()
if (($# == 0)); then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
  cd "$SCRIPT_DIR/.." || exit 2
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "check-pipefail-grep-q: the default scan lists files with git, and $PWD is not a git work tree" >&2
    exit 2
  fi
  while IFS= read -r -d '' f; do
    # awk reads an operand shaped like name=value as an assignment, not a file.
    [[ "$f" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && f="./$f"
    [[ -f "$f" ]] && files+=("$f")
  done < <(git ls-files -z --cached --others --exclude-standard -- '*.sh' | LC_ALL=C sort -z)
  if ((${#files[@]} == 0)); then
    echo "check-pipefail-grep-q: no shell files found in the work tree" >&2
    exit 2
  fi
  BASELINE="${PIPEFAIL_GREP_Q_BASELINE:-scripts/pipefail-grep-q-baseline.txt}"
  if [[ -e "$BASELINE" ]]; then
    # shellcheck source=lib/read-list.sh
    . "$SCRIPT_DIR/lib/read-list.sh" || exit 2
    # shellcheck disable=SC2310  # the non-zero return IS the handled case
    read_list::into baseline "$BASELINE" --comments inline || exit 2
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
# o[] is the masked view; si[] maps each masked char back to its source index.
# ek[] says what grep would see for a masked "_": l a quoted literal char, x a
# quote or escape removed by the shell, n an expansion (neutral in the option
# scan). A char left unmasked is code, kind c. Set EK just before an emit.
function emit(ch,   j) {
  o[++k] = ch; ol[k] = line; si[k] = EP++
  ek[k] = ch != "_" ? "c" : inexp() ? "n" : EK
  EK = "n"
  # dp[]: how many substitution or expansion frames ($( ), backticks, ${ },
  # $(( ))) enclose this char; quote frames do not count. unquoted() reads a
  # char deeper than the start of its word as neutral.
  dp[k] = 0
  for (j = 2; j <= sp; j++) if (ft[j] != "D" && ft[j] != "S" && ft[j] != "E") dp[k]++
}
function inexp(   j) {
  for (j = 1; j <= sp; j++) if (ft[j] == "B" || ft[j] == "A") return 1
  return 0
}
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
  k = 0; line = 1; sp = 0; hn = 0; incomment = 0; EK = "n"; VR = 0
  push("C", 0)
  len = length(S)
  for (i = 1; i <= len; i++) {
    c = substr(S, i, 1); t = ft[sp]; EP = i
    if (VR && !(t == "D" && c ~ /[A-Za-z0-9_]/)) VR = 0
    if (c == "\n") {
      emit("\n"); line++; incomment = 0
      if (hn > 0 && (t == "C" || t == "T")) i = heredoc_bodies(i)
      continue
    }
    if (incomment) { emit(" "); continue }
    if (t == "S") { EK = c == "\047" ? "x" : "l"; emit("_"); if (c == "\047") sp--; continue }
    if (t == "E") {
      if (c == "\\") { EK = "x"; emit("_"); i++; if (substr(S, i, 1) == "\n") { emit("\n"); line++ } else { EK = "l"; emit("_") }; continue }
      EK = c == "\047" ? "x" : "l"; emit("_"); if (c == "\047") sp--; continue
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
      } else { EK = "x"; emit("_"); EK = "l"; emit("_") }
      continue
    }
    if (t == "D" || t == "B") {
      if (VR) { emit("_"); continue }
      if (c == "$" && (r = subst_open(i))) { i = r; continue }
      if (t == "D" && c == "$") {
        # "$name" and "$1" are expansions: neutral, like ${...}.
        nc = substr(S, i + 1, 1)
        if (nc ~ /[A-Za-z_]/) { VR = 1; emit("_"); continue }
        if (nc ~ /[0-9@*#?$!-]/) { emit("_"); i++; EP = i; emit("_"); continue }
      }
      if (c == "`") { push("T", 0); emit("_"); continue }
      if (t == "D" && c == "\"") { sp--; EK = "x"; emit("_"); continue }
      if (t == "B") {
        if (c == "}") { sp--; emit("_"); continue }
        if (c == "\"") { push("D", 0); emit("_"); continue }
        if (c == "\047" && ft[sp - 1] != "D") { push("S", 0); emit("_"); continue }
      }
      EK = "l"; emit("_"); continue
    }
    # code: the top level, $( ), or backticks
    if (t == "T" && c == "`") { sp--; emit("_"); continue }
    if (c == "#" && wordstart(i)) { incomment = 1; emit(" "); continue }
    if (c == "\047") { push("S", 0); EK = "x"; emit("_"); continue }
    if (c == "\"") { push("D", 0); EK = "x"; emit("_"); continue }
    if (c == "`") { push("T", 0); emit("_"); continue }
    if (c == "$") {
      nc = substr(S, i + 1, 1)
      if (nc == "\047") { push("E", 0); EK = "x"; emit("_"); EK = "x"; emit("_"); i++; continue }
      if (nc == "\"") { push("D", 0); EK = "x"; emit("_"); EK = "x"; emit("_"); i++; continue }
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
# unquoted(a, b): masked chars a..b-1 as grep would see them: code as is, quoted
# literals as written, quotes and escapes dropped, each expansion char as "_".
# Any char nested deeper than the start of the word (inside a substitution or
# expansion the word opened) is neutral too; a grep inside a substitution
# starts its words at that depth and reads its own options normally.
function unquoted(a, b,   y, r) {
  r = ""
  for (y = a; y < b; y++) {
    if (dp[y] > dp[a]) r = r "_"
    else if (ek[y] == "c") r = r o[y]
    else if (ek[y] == "l") r = r substr(S, si[y], 1)
    else if (ek[y] == "n") r = r "_"
  }
  return r
}
function early_exit(z,   w, zs, ch, ci, name) {
  # z is just past the grep word; parse its arguments up to the command end.
  while (1) {
    z = skipws(z, 0)
    if (z > k || index("\n;|&)", o[z])) return 0
    zs = z; z = readword(z)
    if (W == "") { z++; continue }
    w = unquoted(zs, z)
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

# The lexer reads every character, so the repository-wide scan is split into
# one contiguous slice of the sorted list per CPU, each written to its own file
# and read back in order, which keeps the output the same as a serial run.
cpus="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
[[ "$cpus" =~ ^[1-9][0-9]*$ ]] || cpus=1
per=$(((${#files[@]} + cpus - 1) / cpus))
out_dir="$(mktemp -d)" || exit 2
trap 'rm -rf "$out_dir"' EXIT
pids=()
for ((b = 0; b * per < ${#files[@]}; b++)); do
  LC_ALL=C awk "$LEXER" "${files[@]:b*per:per}" >"$out_dir/$b" &
  pids+=("$!")
done
scan_failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || scan_failed=1
done
findings=""
for ((b = 0; b < ${#pids[@]}; b++)); do
  findings+="$(cat "$out_dir/$b")"$'\n'
done
findings="$(grep -v '^$' <<<"$findings")" || true
if ((scan_failed)); then
  echo "check-pipefail-grep-q: awk failed while scanning" >&2
  exit 2
fi

# A baselined file's findings are known debt; an entry with none left is stale.
# The baseline exempts whole files, so a new pipe in a listed file passes too.
stale=0
if ((${#baseline[@]} > 0)); then
  declare -A listed=()
  for f in "${baseline[@]}"; do listed["$f"]=1; done
  kept=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    f="${line#PIPED EARLY-EXIT GREP: }"
    f="${f%%:[0-9]*: *}"
    f="${f#./}"
    if [[ -n "${listed[$f]:-}" ]]; then
      read_list::mark_used "$f"
    else
      kept+="$line"$'\n'
    fi
  done <<<"$findings"
  findings="${kept%$'\n'}"
  # shellcheck disable=SC2310  # the non-zero return IS the handled case
  read_list::report_stale baseline "$BASELINE" "has no piped early-exit grep left, or is gone; delete its line" || stale=1
fi

if [[ -z "$findings" ]] && ((stale == 0)); then
  echo "No piped early-exit grep in ${#files[@]} shell file(s); ${#baseline[@]} baselined file(s) still to fix."
  exit 0
fi

if [[ -n "$findings" ]]; then
  printf '%s\n' "$findings" >&2
  count="$(grep -c '' <<<"$findings")"
  echo "$count piped early-exit grep(s) found; rewrite each as grep ... <<<\"\$v\" or grep ... < <(producer)." >&2
fi
exit 1
