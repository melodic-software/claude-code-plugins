# cant-fail-scan.awk — per-file rule engine for cant-fail-scan.sh. Not a
# standalone entry point: the driver resolves the scan root, walks the tree,
# picks the adapter for each file, and aggregates; this program judges ONE test
# file per invocation.
#
# Invocation: awk -v ADAPTER=<id> -v ADAPTER_TABLE=<path> [-v SCOPE=<n[-m],...>] -f mask-js.awk -f cant-fail-scan.awk <file>
#
# ADAPTER_TABLE is adapter-load.awk's output over the adapters/ directory. All
# framework vocabulary (test starts, skips, assertion tokens, mocks, equality
# helpers) comes from the named adapter. This file holds only what no adapter
# can supply: the rules, one lexer per language family (js, cs, python), and
# the block model each lexer drives (brace for js and cs, indent for python).
# Language syntax stays with its lexer: C# attributes and method signatures,
# and Python's assert statement.
#
# Twin-file load: the JavaScript masker lives in mask-js.awk beside this file,
# because runner-config-scan.awk masks the same language and one copy cannot
# drift from itself. The driver passes both -f flags; this program calls
# mask_js() and never defines it.
#
# Output, tab-separated, one record per line:
#   F <tab> <rule-slug> <tab> <line> <tab> <detail>   a finding
#   X <tab> <rule-slug> <tab> <line> <tab> <detail>   a finding exempted by a cant-fail-ok: annotation
#   B <tab> <count>                                    test blocks parsed (emitted once, at END)
#
# Rule slugs: zero-assertion | recomputed-expectation | mock-only-oracle.
# The driver owns the qualified rule-id form and the thresholds' prose.
#
# Design bias, load-bearing: every heuristic errs toward NOT firing. Assertion
# tokens are matched generously (a helper named checkInvariant counts), string
# and comment text is masked before any token match, skipped tests are not
# judged, and a mock-assertion chain the stripper cannot parse is treated as a
# value assertion. A missed defect costs one finding; a false positive costs
# the detector its audience.

BEGIN {
  blocks = 0
  in_test = 0
  pending_skip = 0
  pending_attr = 0
  file_mock = 0
  prev_raw = ""
  FATAL = 0
  sr = 0        # inside a skipped suite (describe.skip / xdescribe) — JS only  # spellchecker:disable-line
  sr_depth = 0
  last_sig = "" # last significant code char emitted by mask_js — regex-vs-division context
  NS = split(SCOPE, scope_parts, ",")
  for (i = 1; i <= NS; i++) {
    S_LO[i] = S_HI[i] = scope_parts[i] + 0
    if (scope_parts[i] ~ /-/) S_HI[i] = substr(scope_parts[i], index(scope_parts[i], "-") + 1) + 0
  }
  load_adapter()
}

# ---------------------------------------------------------------------------
# Adapter. Each list field joins into one alternation; an empty list becomes
# "", which has() treats as never matching. The R_* names are the parity
# check's contract (parity-check.sh dumps them).
# ---------------------------------------------------------------------------

function load_adapter(    line, f, key, n, i, w, nw, wi) {
  while ((getline line < ADAPTER_TABLE) > 0) {
    split(line, f, "\t")
    if (f[1] != ADAPTER) continue
    key = f[2]
    if (key == "language") LEXER = f[3]
    else if (key == "suppress_marker") R_EXEMPT = f[3]
    # Two statements: mawk creates V[key] before evaluating the right side.
    else if (key in V) V[key] = V[key] "|" f[3]
    else V[key] = f[3]
  }
  close(ADAPTER_TABLE)
  if (LEXER == "") {
    printf "E\tunknown adapter '%s'\n", ADAPTER
    FATAL = 1
    exit 2
  }
  SHELL_LEX = LEXER == "bash" || LEXER == "pwsh"
  MODEL = V["block_model"]
  if (MODEL == "") MODEL = LEXER == "python" ? "indent" : "brace"
  R_ANY = V["assertion.calls"]
  if (V["snapshot"] != "") R_ANY = R_ANY (R_ANY != "" ? "|" : "") V["snapshot"]
  # Matched against raw text over a three-line window (append_block).
  R_RAW = V["assertion.idioms"]
  if (V["delegation"] != "") R_RAW = R_RAW (R_RAW != "" ? "|" : "") V["delegation"]
  R_BODY_SKIP = V["body_skip"]
  N_PIPE = (V["equality.pipeline"] == "") ? 0 : split(V["equality.pipeline"], PIPE, "|")
  R_MOCKA = V["mock.verify"]
  R_MOCKC = V["mock.create"]
  R_STRIP = V["mock.strip"]
  R_START = V["test_start"]
  R_SKIP = V["test_skip"]
  R_SUITE_SKIP = V["suite_skip"]
  if (R_EXEMPT == "") R_EXEMPT = "cant-fail-ok:"

  # Two-argument equality helpers, matched by substring in list order.
  # Inequality asserts are never listed: Assert.NotEqual(f(2), f(2)) is an
  # always-fail defect, not this rule.
  R_CALL2 = V["equality.call2"]
  N_CALL2 = (R_CALL2 == "") ? 0 : split(R_CALL2, CALL2, "|")

  # Receiver form <wrapper>.<matcher>: wrapper(A).matcher(B). Grouped by
  # wrapper into one matcher alternation each.
  NRW = 0
  n = (V["equality.receiver"] == "") ? 0 : split(V["equality.receiver"], w, "|")
  for (i = 1; i <= n; i++) {
    nw = index(w[i], ".")
    for (wi = 1; wi <= NRW && RW_NAME[wi] != substr(w[i], 1, nw - 1); wi++) ;
    if (wi > NRW) { NRW = wi; RW_NAME[wi] = substr(w[i], 1, nw - 1); RW_MATCH[wi] = "" }
    RW_MATCH[wi] = RW_MATCH[wi] (RW_MATCH[wi] != "" ? "|" : "") substr(w[i], nw + 1)
  }
}

function has(s, re) { return re != "" && s ~ re }

# ---------------------------------------------------------------------------
# Masking. One function per language; string/comment interiors become spaces,
# LENGTH-PRESERVING, so token matches and brace counts run over code only and
# raw/masked column positions stay aligned. Multi-line states (block comments,
# template literals, triple quotes, verbatim strings) are file-scoped globals.
# mask_js is shared with runner-config-scan.awk and lives in mask-js.awk, which
# the driver loads as the first -f program.
# ---------------------------------------------------------------------------

function mask_py(s,    out, i, c, c3, n) {
  out = ""; n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1); c3 = substr(s, i, 3)
    if (S_triple) {
      if (c3 == S_tq) { S_triple = 0; out = out "   "; i += 3 } else { out = out " "; i++ }
      continue
    }
    if (S_str) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == S_q) S_str = 0
      out = out " "; i++; continue
    }
    if (c == "#") { while (i <= n) { out = out " "; i++ }; continue }
    if (c3 == "'''" || c3 == "\"\"\"") { S_triple = 1; S_tq = c3; out = out "   "; i += 3; continue }
    if (c == "'" || c == "\"") { S_str = 1; S_q = c; out = out " "; i++; continue }
    out = out c; i++
  }
  S_str = 0
  return out
}

function mask_cs(s,    out, i, c, c2, c3, n) {
  out = ""; n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i, 2); c3 = substr(s, i, 3)
    if (S_bc) { if (c2 == "*/") { S_bc = 0; out = out "  "; i += 2 } else { out = out " "; i++ }; continue }
    if (S_verb) {
      if (c2 == "\"\"") { out = out "  "; i += 2; continue }
      if (c == "\"") S_verb = 0
      out = out " "; i++; continue
    }
    if (S_str) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == S_q) S_str = 0
      out = out " "; i++; continue
    }
    if (c2 == "//") { while (i <= n) { out = out " "; i++ }; continue }
    if (c2 == "/*") { S_bc = 1; out = out "  "; i += 2; continue }
    if (c3 == "$@\"" || c3 == "@$\"") { S_verb = 1; out = out "   "; i += 3; continue }
    if (c2 == "@\"") { S_verb = 1; out = out "  "; i += 2; continue }
    if (c2 == "$\"") { S_str = 1; S_q = "\""; out = out "  "; i += 2; continue }
    if (c == "\"" || c == "'") { S_str = 1; S_q = c; out = out " "; i++; continue }
    out = out c; i++
  }
  S_str = 0
  return out
}

function blanks(n,    out) { out = ""; while (n-- > 0) out = out " "; return out }

# A "#" opens a comment only at the start of a word, so $# and ${#x} stay code.
function word_start(s, i) { return i == 1 || substr(s, i - 1, 1) ~ /[[:space:];|&({]/ }

# Bash and bats. Strings may span lines; a heredoc body is masked to its
# terminator line (<<-TAG allows leading tabs there).
function mask_sh(s,    out, i, c, n, t, k, q) {
  if (S_hd) {
    t = s
    if (S_hd_dash) sub(/^\t+/, "", t)
    if (t == S_hd_tag) S_hd = 0
    return blanks(length(s))
  }
  out = ""; n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (S_str) {
      if (c == "\\" && S_q != "'") { out = out "  "; i += 2; continue }
      if (c == (S_q == "\"" ? "\"" : "'")) S_str = 0
      out = out " "; i++; continue
    }
    if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
    if (c == "#" && word_start(s, i)) { out = out blanks(n - i + 1); break }
    if (c == "$" && substr(s, i + 1, 1) == "'") { S_str = 1; S_q = "e"; out = out "  "; i += 2; continue }
    if (c == "'" || c == "\"") { S_str = 1; S_q = c; out = out " "; i++; continue }
    if (substr(s, i, 2) == "<<" && substr(s, i, 3) != "<<<") {
      t = substr(s, i + 2); k = 2; S_hd_dash = 0
      if (t ~ /^-/) { S_hd_dash = 1; t = substr(t, 2); k++ }
      match(t, /^[[:space:]]*/); k += RLENGTH; t = substr(t, RLENGTH + 1)
      q = substr(t, 1, 1)
      if (q == "'" || q == "\"") t = substr(t, 2); else q = ""
      if (match(t, /^[A-Za-z_][A-Za-z0-9_]*/)) {
        S_hd_next = substr(t, 1, RLENGTH)
        k += RLENGTH + (q != "") + (q != "" && substr(t, RLENGTH + 1, 1) == q)
      }
      out = out "<<" blanks(k - 2); i += k; continue
    }
    out = out c; i++
  }
  if (S_hd_next != "") { S_hd = 1; S_hd_tag = S_hd_next; S_hd_next = "" }
  return out
}

# PowerShell. <# #> block comments, here-strings (@' or @" ending a line,
# closed by '@ or "@ opening one), '' and backtick escapes.
function mask_ps(s,    out, i, c, c2, n) {
  if (S_hs != "") {
    if (substr(s, 1, 2) == S_hs "@") { S_hs = ""; return "  " substr(s, 3) }
    return blanks(length(s))
  }
  out = ""; n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i, 2)
    if (S_bc) { if (c2 == "#>") { S_bc = 0; out = out "  "; i += 2 } else { out = out " "; i++ }; continue }
    if (S_str) {
      if (c == "`" && S_q == "\"") { out = out "  "; i += 2; continue }
      if (c == S_q) {
        if (substr(s, i + 1, 1) == S_q) { out = out "  "; i += 2; continue }
        S_str = 0
      }
      out = out " "; i++; continue
    }
    if (c2 == "<#") { S_bc = 1; out = out "  "; i += 2; continue }
    if (c == "#" && word_start(s, i)) { out = out blanks(n - i + 1); break }
    if ((c2 == "@'" || c2 == "@\"") && substr(s, i + 2) ~ /^[[:space:]]*$/) { S_hs = substr(c2, 2, 1); out = out blanks(n - i + 1); break }
    if (c == "`") { out = out substr(s, i, 2); i += 2; continue }
    if (c == "'" || c == "\"") { S_str = 1; S_q = c; out = out " "; i++; continue }
    out = out c; i++
  }
  return out
}

# Go. Interpreted strings and runes end on their line; raw `strings` may not.
function mask_go(s,    out, i, c, c2, n) {
  out = ""; n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i, 2)
    if (S_bc) { if (c2 == "*/") { S_bc = 0; out = out "  "; i += 2 } else { out = out " "; i++ }; continue }
    if (S_raw) { if (c == "`") S_raw = 0; out = out " "; i++; continue }
    if (S_str) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == S_q) S_str = 0
      out = out " "; i++; continue
    }
    if (c2 == "//") { out = out blanks(n - i + 1); break }
    if (c2 == "/*") { S_bc = 1; out = out "  "; i += 2; continue }
    if (c == "`") { S_raw = 1; out = out " "; i++; continue }
    if (c == "\"" || c == "'") { S_str = 1; S_q = c; out = out " "; i++; continue }
    out = out c; i++
  }
  S_str = 0
  return out
}

# A string, heredoc or comment still open at end of file means the masker lost
# sync; the new lexers then report nothing rather than a guess.
function mask_open() {
  if (LEXER == "bash") return S_str || S_hd
  if (LEXER == "pwsh") return S_str || S_bc || S_hs != ""
  if (LEXER == "go") return S_bc || S_raw
  return 0
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

function brace_delta(s,    i, n, c, d) {
  d = 0; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == "{") d++
    else if (c == "}") d--
  }
  return d
}

function indent_of(s,    i, n, c, w) {
  w = 0; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (c == " ") w++
    else if (c == "\t") w += 8
    else break
  }
  return w
}

function norm(s) { gsub(/[[:space:]]+/, "", s); return s }

function clean_detail(s) { gsub(/\t/, " ", s); return s }

function count_matches(s, re,    c) {
  c = 0
  while (match(s, re) > 0) {
    c++
    s = substr(s, RSTART + (RLENGTH > 0 ? RLENGTH : 1))
  }
  return c
}

function first_quoted(s,    q, rest, j) {
  # first '…' / "…" / `…` payload after the leading token, for a test name
  if (match(s, /['"`]/) == 0) return "(unnamed)"
  q = substr(s, RSTART, 1)
  rest = substr(s, RSTART + 1)
  j = index(rest, q)
  if (j <= 1) return "(unnamed)"
  return substr(rest, 1, j - 1)
}

# Balanced-( extraction. s[from] must be "(". Sets EXTRACT (interior) and
# EXTEND (index of the closing paren); returns 1 on success. Quote-aware so a
# ")" inside a string argument does not close the group early.
function extract_parens(s, from,    i, n, c, d, q, out) {
  n = length(s)
  if (substr(s, from, 1) != "(") return 0
  d = 0; q = ""; out = ""
  for (i = from; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == "\\") { out = out substr(s, i, 2); i++; continue }
      if (c == q) q = ""
      out = out c
      continue
    }
    if (c == "'" || c == "\"" || c == "`") { q = c; out = out c; continue }
    if (c == "(") { d++; if (d == 1) continue }
    if (c == ")") { d--; if (d == 0) { EXTRACT = out; EXTEND = i; return 1 } }
    out = out c
  }
  return 0
}

# First top-level comma split of s. Sets SPLIT1 / SPLIT2; returns 1 when a
# top-level comma exists.
function split_top_comma(s,    i, n, c, d, q) {
  n = length(s); d = 0; q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == "\\") { i++; continue }
      if (c == q) q = ""
      continue
    }
    if (c == "'" || c == "\"" || c == "`") { q = c; continue }
    if (c == "(" || c == "[" || c == "{") d++
    else if (c == ")" || c == "]" || c == "}") d--
    else if (c == "," && d == 0) { SPLIT1 = substr(s, 1, i - 1); SPLIT2 = substr(s, i + 1); return 1 }
  }
  return 0
}

# Exactly-one top-level "==" split. Sets EQL / EQR; returns 1 on success.
function split_top_eq(s,    i, n, c, d, q, hits, pos) {
  n = length(s); d = 0; q = ""; hits = 0; pos = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") {
      if (c == "\\") { i++; continue }
      if (c == q) q = ""
      continue
    }
    if (c == "'" || c == "\"" || c == "`") { q = c; continue }
    if (c == "(" || c == "[" || c == "{") d++
    else if (c == ")" || c == "]" || c == "}") d--
    else if (d == 0 && substr(s, i, 2) == "==") {
      if (substr(s, i, 3) == "===") { i += 2; continue }
      if (i > 1 && substr(s, i - 1, 1) ~ /[!<>=]/) { i++; continue }
      hits++; pos = i; i++
    }
  }
  if (hits != 1 || pos == 0) return 0
  EQL = substr(s, 1, pos - 1); EQR = substr(s, pos + 2)
  return 1
}

# One shell word from s[i]: quotes, and $( ) or ( ) groups, stay inside it.
# Sets SW and returns the index just past it.
function shell_word(s, i,    n, c, q, d, out) {
  n = length(s); q = ""; d = 0; out = ""
  for (; i <= n; i++) {
    c = substr(s, i, 1)
    if (d > 0) {
      if (c == "(") d++
      else if (c == ")") d--
    } else if (q != "") {
      if (c == "\\" && q == "\"") { out = out substr(s, i, 2); i++; continue }
      if (c == q) q = ""
      else if (c == "(" && substr(s, i - 1, 1) == "$") d++
    } else if (c ~ /[[:space:];|&]/) break
    else if (c == "'" || c == "\"") q = c
    else if (c == "(") d++
    out = out c
  }
  SW = out
  return i
}

# The first two shell words at or after s[i]. Sets SW1 / SW2; returns 1 when
# both exist.
function shell_words(s, i) {
  while (substr(s, i, 1) ~ /[[:space:]]/) i++
  i = shell_word(s, i); SW1 = SW
  while (substr(s, i, 1) ~ /[[:space:]]/) i++
  shell_word(s, i); SW2 = SW
  return SW1 != "" && SW2 != ""
}

# Drop one wrapping ( ) or $( ), so (f 2) and f 2 compare equal.
function unparen(s) {
  if (s ~ /^\$?\(.*\)$/) { sub(/^\$?\(/, "", s); sub(/\)$/, "", s) }
  return s
}

# SCOPE (driver --lines) keeps only findings whose test block overlaps one of
# its ranges. A line-scoped finding inside an open block waits in PEND until
# the block closes and its extent is known.
function in_scope(lo, hi,    i) {
  for (i = 1; i <= NS; i++) if (S_LO[i] <= hi && S_HI[i] >= lo) return 1
  return 0
}

function emit(kind, slug, line, detail,    rec) {
  rec = sprintf("%s\t%s\t%d\t%s\n", kind, slug, line, clean_detail(detail))
  if (SCOPE == "") printf "%s", rec
  else if (closing) { if (in_scope(block_line, block_hi)) printf "%s", rec }
  else if (in_test) PEND = PEND rec
  else if (FNR == closed_at && MODEL != "indent" ? in_scope(closed_lo, block_hi) : in_scope(line, line)) printf "%s", rec
}

# ---------------------------------------------------------------------------
# CF2 — recomputed expectation (self-identical actual/expected), line-scoped.
# The masked line gates (no findings from comments or strings); the raw line
# is what the expressions are read from.
# ---------------------------------------------------------------------------

function taut_scan(raw_line, masked_line,    tkind, a, b, rest, m, i, p, fn, expr, wrap_re) {
  tkind = (raw_line ~ R_EXEMPT || prev_raw ~ R_EXEMPT) ? "X" : "F"
  # Receiver form, e.g. expect(A).toBe(A). The masked match position indexes
  # into the RAW line — masking is length-preserving, so the columns align,
  # and an earlier "expect" inside a string cannot shadow the real call site.
  for (i = 1; i <= NRW; i++) {
    wrap_re = RW_NAME[i]
    gsub(/\./, "\\.", wrap_re)
    if (match(masked_line, wrap_re "[[:space:]]*\\(") == 0) continue
    m = RSTART + length(RW_NAME[i])
    while (substr(raw_line, m, 1) ~ /[[:space:]]/) m++
    if (!extract_parens(raw_line, m)) continue
    a = EXTRACT
    rest = substr(raw_line, EXTEND + 1)
    if (match(rest, "^[[:space:]]*\\.[[:space:]]*(" RW_MATCH[i] ")[[:space:]]*\\(") == 0) continue
    p = index(rest, "(")
    if (p > 0 && extract_parens(rest, p)) {
      b = EXTRACT
      expr = norm(a)
      if (expr != "" && expr == norm(b)) {
        emit(tkind, "recomputed-expectation", FNR, RW_NAME[i] "(" expr ") compared to itself")
        return
      }
    }
  }
  # two-argument equality helpers
  for (i = 1; i <= N_CALL2; i++) {
    fn = CALL2[i]
    if (index(masked_line, fn) == 0) continue
    p = index(raw_line, fn)
    if (p == 0) continue
    m = p + length(fn)
    # Shell command form: fn A B, fn a whole word, A and B its first two words.
    if (SHELL_LEX && word_start(raw_line, p) && substr(raw_line, m, 1) ~ /[[:space:]]/) {
      if (!shell_words(raw_line, m)) continue
      expr = norm(SW1)
      if (expr != "" && expr == norm(SW2)) {
        emit(tkind, "recomputed-expectation", FNR, fn " " expr " " expr)
        return
      }
      continue
    }
    while (substr(raw_line, m, 1) ~ /[[:space:]]/) m++
    if (!extract_parens(raw_line, m)) continue
    if (!split_top_comma(EXTRACT)) continue
    a = SPLIT1; b = SPLIT2
    if (split_top_comma(b)) b = SPLIT1  # drop trailing message/args
    expr = norm(a)
    if (expr != "" && expr == norm(b)) {
      emit(tkind, "recomputed-expectation", FNR, fn "(" expr ", " expr ")")
      return
    }
  }
  # pipeline form, e.g. A | Should -Be A: A runs from the statement start to
  # the last pipe before the matcher; the other side is the matcher's first word.
  for (i = 1; i <= N_PIPE; i++) {
    wrap_re = PIPE[i]
    gsub(/[.]/, "\\.", wrap_re)
    gsub(/ /, "[[:space:]]+", wrap_re)
    if (match(masked_line, "\\|[[:space:]]*" wrap_re "([[:space:]]|$)") == 0) continue
    rest = substr(masked_line, 1, RSTART - 1)
    m = RSTART + RLENGTH
    for (p = length(rest); p > 0 && substr(rest, p, 1) !~ /[;{]/; p--) ;
    a = substr(raw_line, p + 1, length(rest) - p)
    shell_words(raw_line, m)
    b = SW1
    expr = unparen(norm(a))
    if (expr != "" && expr == unparen(norm(b))) {
      emit(tkind, "recomputed-expectation", FNR, expr " | " PIPE[i] " " expr)
      return
    }
  }
  # python assert EXPR == EXPR: the statement is language syntax, not adapter data
  if (LEXER == "python" && masked_line ~ /^[[:space:]]*assert[[:space:]]/) {
    rest = raw_line
    sub(/^[[:space:]]*assert[[:space:]]+/, "", rest)
    if (split_top_comma(rest)) rest = SPLIT1  # drop ", msg"
    if (split_top_eq(rest)) {
      expr = norm(EQL)
      if (expr != "" && expr == norm(EQR)) {
        emit(tkind, "recomputed-expectation", FNR, "assert " expr " == " expr)
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Block evaluation — CF1 and CF3
# ---------------------------------------------------------------------------

function eval_block(    blk, stripped, mocka_n, kind) {
  blk = block_masked
  # A test that skips itself from inside its body does not run: not judged.
  if (has(blk, R_BODY_SKIP)) return
  blocks++
  if (block_raw) return
  kind = block_exempt ? "X" : "F"
  if (!has(blk, R_ANY) && !has(blk, R_MOCKA)) {
    emit(kind, "zero-assertion", block_line, "test '" block_name "' has 0 assertion tokens")
    return
  }
  if ((has(blk, R_MOCKC) || file_mock) && has(blk, R_MOCKA)) {
    stripped = blk
    if (R_STRIP != "") gsub(R_STRIP, "", stripped)
    if (!has(stripped, R_ANY)) {
      mocka_n = count_matches(blk, R_MOCKA)
      emit(kind, "mock-only-oracle", block_line, "test '" block_name "': " mocka_n " mock-interaction assertion(s), no assertion on a real collaborator detected")
    }
  }
}

function open_block(line, name) {
  in_test = 1
  block_line = block_last = line
  block_name = name
  block_masked = ""
  block_exempt = (raw ~ R_EXEMPT || prev_raw ~ R_EXEMPT)
  block_raw = 0; BW1 = BW2 = ""
}

# block_raw: an idiom or a delegation matched the raw text of this line and
# the two before it, which counts as an assertion.
function append_block(m, r) {
  block_masked = block_masked m "\n"
  block_last = FNR
  if (r ~ R_EXEMPT) block_exempt = 1
  if (R_RAW != "" && !block_raw) {
    if ((BW2 " " BW1 " " r) ~ R_RAW) block_raw = 1
    BW2 = BW1; BW1 = r
  }
}

function close_block() {
  in_test = 0
  # A brace block ends on its closing line; an indent block closes on the
  # next dedented line, so its extent ends at the last line it took.
  block_hi = MODEL == "indent" ? block_last : FNR
  closed_lo = block_line; closed_at = FNR
  if (PEND != "" && in_scope(block_line, block_hi)) printf "%s", PEND
  PEND = ""
  closing = 1; eval_block(); closing = 0
}

# A C# test body starting on this line: a "{" opens a brace body, a "=>" opens
# an expression body that a trailing ";" closes on the same line.
function cs_body_start(m) {
  if (index(m, "{") > 0) {
    body_open = 1
    depth = brace_delta(m)
    if (depth <= 0) close_block()
  } else if (index(m, "=>") > 0) {
    expr_body = 1
    if (m ~ /;[[:space:]]*$/) { expr_body = 0; close_block() }
  }
}

function cs_method_name(s,    t) {
  t = s
  sub(/\(.*$/, "", t)
  if (match(t, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/) > 0) {
    t = substr(t, RSTART, RLENGTH)
    gsub(/[[:space:]]/, "", t)
    return t
  }
  return "(unnamed)"
}

# ---------------------------------------------------------------------------
# Block models. brace_call: a test_start call opens a brace block on its own
# line (js). brace_decl: test_start attributes, then a method signature opens a
# brace or expression body (cs). indent: a test_start def opens a block its
# indentation closes (python).
# ---------------------------------------------------------------------------

function brace_call() {
  if (in_test) {
    append_block(masked, raw)
    depth += brace_delta(masked)
    if (depth <= 0) close_block()
    taut_scan(raw, masked)
  } else if (sr) {
    # inside a skipped suite: consume braces until the suite closes; open
    # nothing and judge nothing — a test that does not run is not judged
    sr_depth += brace_delta(masked)
    if (sr_depth <= 0) sr = 0
  } else if (has(masked, R_SUITE_SKIP)) {
    match(masked, R_SUITE_SKIP)
    sr = 1
    sr_depth = brace_delta(substr(masked, RSTART))
    if (sr_depth <= 0) sr = 0
  } else {
    if (has(masked, R_START) && !has(masked, R_SKIP)) {
      match(masked, R_START)
      open_block(FNR, LEXER == "go" ? cs_method_name(substr(masked, RSTART)) : first_quoted(substr(raw, RSTART)))
      append_block(masked, raw)
      depth = brace_delta(substr(masked, RSTART))
      if (depth <= 0) close_block()
    }
    taut_scan(raw, masked)
  }
}

# file: the whole file is one test, named by its basename (bash harnesses).
function whole_file(    n, parts) {
  if (!in_test) {
    n = split(FILENAME, parts, "/")
    open_block(FNR, parts[n])
  }
  append_block(masked, raw)
  taut_scan(raw, masked)
}

# test_skip here matches a decorator on a line above the def.
function indent() {
  if (in_test && masked !~ /^[[:space:]]*$/ && indent_of(raw) <= def_indent) close_block()
  if (!in_test) {
    if (has(masked, R_SKIP)) pending_skip = 1
    if (has(masked, R_START)) {
      if (pending_skip) pending_skip = 0
      else {
        match(masked, /def[[:space:]]+[A-Za-z0-9_]*/)
        open_block(FNR, substr(masked, RSTART + 4, RLENGTH - 4))
        sub(/^[[:space:]]+/, "", block_name)
        def_indent = indent_of(raw)
        append_block(masked, raw)
      }
    } else if (masked !~ /^[[:space:]]*@/ && masked !~ /^[[:space:]]*$/) pending_skip = 0
  } else append_block(masked, raw)
  taut_scan(raw, masked)
}

# test_skip here matches any attribute in the stack, before or after the test
# attribute. An attribute is a line opening with "["; a signature is a line
# with a C# modifier or return type before its "(".
function brace_decl() {
  if (in_test) {
    if (expr_body) {
      append_block(masked, raw)
      if (masked ~ /;[[:space:]]*$/) { expr_body = 0; close_block() }
    } else if (body_open) {
      append_block(masked, raw)
      depth += brace_delta(masked)
      if (depth <= 0) close_block()
    } else {
      append_block(masked, raw)
      cs_body_start(masked)
    }
  } else if (pending_attr && masked ~ /(public|private|protected|internal|async|static|void|Task)[^=]*\(/ && masked !~ /^[[:space:]]*\[/) {
    pending_attr = 0
    if (pending_skip) pending_skip = 0
    else {
      open_block(FNR, cs_method_name(masked))
      append_block(masked, raw)
      body_open = 0; expr_body = 0; depth = 0
      cs_body_start(masked)
    }
  } else {
    if (has(masked, R_START)) {
      pending_attr = 1
      if (has(masked, R_SKIP)) pending_skip = 1
    } else if (masked ~ /^[[:space:]]*\[/) {
      # any other attribute in the same stack — a skip marker counts whether
      # it precedes or follows the test attribute
      if (has(masked, R_SKIP)) pending_skip = 1
    } else if (masked !~ /^[[:space:]]*$/) { pending_attr = 0; pending_skip = 0 }
  }
  taut_scan(raw, masked)
}

# ---------------------------------------------------------------------------
# Main loop: one lexer and one block model per adapter language.
# ---------------------------------------------------------------------------

{
  raw = $0
  sub(/\r$/, "", raw)
  if (LEXER == "js") masked = mask_js(raw)
  else if (LEXER == "python") masked = mask_py(raw)
  else if (LEXER == "bash") masked = mask_sh(raw)
  else if (LEXER == "pwsh") masked = mask_ps(raw)
  else if (LEXER == "go") masked = mask_go(raw)
  else masked = mask_cs(raw)

  if (has(masked, R_MOCKC)) file_mock = 1

  if (MODEL == "file") whole_file()
  else if (MODEL == "indent") indent()
  else if (LEXER == "cs") brace_decl()
  else brace_call()
  prev_raw = raw
}

END {
  if (FATAL) exit 2
  if (in_test && !mask_open()) close_block()
  printf "B\t%d\n", blocks
}
