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
# can supply: the rules, one lexer per language (js, cs, python, bash, pwsh,
# go), and the block models the adapter picks (brace, indent for python, file
# for a harness with no per-case marker).
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
#   S <tab> <F|X> <tab> <line> <tab> <path>           a source-text-read candidate: a static path a
#                                                      test reads; the driver keeps it only when git
#                                                      tracks it as a non-test source file
#   B <tab> <count>                                    test blocks parsed (emitted once, at END)
#   L <tab> 1                                          the lexer ended inside a string, heredoc or comment; the open block is not judged
#
# -v INVENTORY=<n> replaces all of the above with an inventory of the text,
# counted per masked line whatever the block model sees, so a fragment with no
# test start still counts (the test-weaken hook compares two of these):
#   <n> <tab> test|assertion|skip <tab> <count> <tab> <line>   test_start, assertion
#                                                      (calls, snapshot, mock.verify) and
#                                                      test_skip/body_skip/suite_skip matches on a line
#   <n> <tab> expect <tab> <actual> <tab> <literal>    an equality with one literal side
#   <n> <tab> unjudged                                 the lexer ended inside a string or comment
#
# Rule slugs: zero-assertion | recomputed-expectation | mock-only-oracle |
# inert-assertion | constant-restatement | conditional-assertion |
# recomputed-derived | snapshot-only | weak-oracle (source-text-read comes
# from S).
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
  skip_cls = -1
  file_mock = 0
  prev_raw = ""
  FATAL = 0
  sr = 0        # inside a skipped suite (describe.skip / xdescribe) or C# class  # spellchecker:disable-line
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
  # Statement-initial forms: anchored here, so an adapter lists bare starts.
  R_ASYNC = V["assertion.async"] == "" ? "" : "^(" V["assertion.async"] ")"
  R_INERT = V["assertion.inert"] == "" ? "" : "^(" V["assertion.inert"] ")"
  R_WEAK = V["assertion.weak"]
  R_SNAP = V["snapshot"]
  R_COUNT = V["assertion.count"]
  R_FAILC = V["assertion.fail"]
  RULES_OFF = "|" V["rules_off"] "|"
  # A property marker anywhere in the file exempts every test in it, so the
  # file is read once up front: a marker below the first test comes too late.
  PROP_FILE = 0
  if (V["property_markers"] != "" && ARGV[1] != "") {
    while ((getline line < ARGV[1]) > 0) if (line ~ V["property_markers"]) { PROP_FILE = 1; break }
    close(ARGV[1])
  }
  # C#: a statement-initial Verify( is Verify's snapshot only in a file that
  # imports a Verify package and declares no Verify method of its own.
  CS_VERIFY = 0
  if (LEXER == "cs" && ARGV[1] != "") {
    while ((getline line < ARGV[1]) > 0) {
      if (line ~ /using[[:space:]]+(static[[:space:]]+)?Verify(Xunit|NUnit|MSTest|Tests)([^A-Za-z0-9_]|$)|\[[[:space:]]*UsesVerify/) CS_VERIFY = 1
      if (line !~ /^[[:space:]]*(return|await)[[:space:]]/ && line ~ /^[[:space:]]*([A-Za-z]+[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.?]*[[:space:]]+Verify(Json|Xml|File)?[[:space:]]*(<[^<>]*>)?[[:space:]]*\(/) { CS_VERIFY = 0; break }
    }
    close(ARGV[1])
  }
  # C#: RunAsync on an object initializer is Microsoft.CodeAnalysis.Testing's
  # analyzer or code-fix harness, which asserts the diagnostics and fixed
  # code, only in a file that imports that harness or aliases one of its types.
  if (LEXER == "cs" && ARGV[1] != "") {
    while ((getline line < ARGV[1]) > 0)
      if (line ~ /^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*)?Microsoft\.CodeAnalysis(\.[A-Za-z]+)*\.Testing([^A-Za-z0-9_]|$)/) {
        R_ANY = R_ANY "|\\}[[:space:]]*\\.[[:space:]]*RunAsync[[:space:]]*\\("
        break
      }
    close(ARGV[1])
  }

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
      # "$( ... )" is code again, with its own quotes, until its ")".
      if (S_q == "\"" && substr(s, i, 2) == "$(") { S_str = 0; S_sub[++S_nsub] = 0; out = out "$("; i += 2; continue }
      if (c == (S_q == "\"" ? "\"" : "'")) S_str = 0
      out = out " "; i++; continue
    }
    if (S_nsub > 0 && c == "(") S_sub[S_nsub]++
    if (S_nsub > 0 && c == ")" && S_sub[S_nsub]-- == 0) { S_nsub--; S_str = 1; S_q = "\""; out = out ")"; i++; continue }
    if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
    # ${#x} is a length, not a comment: "{" starts no word in bash.
    if (c == "#" && word_start(s, i) && substr(s, i - 1, 1) != "{") { out = out blanks(n - i + 1); break }
    if (c == "$" && substr(s, i + 1, 1) == "'") { S_str = 1; S_q = "e"; out = out "  "; i += 2; continue }
    if (c == "'" || c == "\"") { S_str = 1; S_q = c; out = out " "; i++; continue }
    # A here-string, consumed whole so its last two "<" never read as "<<".
    if (substr(s, i, 3) == "<<<") { out = out "<<<"; i += 3; continue }
    if (substr(s, i, 2) == "<<") {
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
  if (LEXER == "bash") return S_str || S_hd || S_nsub > 0
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

# Net opens over closes in s, for the given opening and closing characters.
function delta(s, opens, closes,    i, n, c, d) {
  d = 0; n = length(s)
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (index(opens, c)) d++
    else if (index(closes, c)) d--
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
  if (INVENTORY || index(RULES_OFF, "|" slug "|")) return
  rec = sprintf("%s\t%s\t%d\t%s\n", kind, slug, line, clean_detail(detail))
  if (SCOPE == "") printf "%s", rec
  else if (closing) { if (in_scope(block_line, block_hi)) printf "%s", rec }
  else if (in_test) PEND = PEND rec
  else if (FNR == closed_at && MODEL != "indent" ? in_scope(closed_lo, block_hi) : in_scope(line, line)) printf "%s", rec
}

# Inventory records (-v INVENTORY). A pattern list the adapter leaves empty
# counts nothing.
function inv_count(s, re) { return re == "" ? 0 : count_matches(s, re) }

function inv_line(    t, n) {
  t = clean_detail(trim(raw))
  if ((n = inv_count(masked, R_START)) > 0) printf "%s\ttest\t%d\t%s\n", INVENTORY, n, t
  if ((n = inv_count(masked, R_ANY) + inv_count(masked, R_MOCKA)) > 0) printf "%s\tassertion\t%d\t%s\n", INVENTORY, n, t
  if ((n = inv_count(masked, R_SKIP) + inv_count(masked, R_BODY_SKIP) + inv_count(masked, R_SUITE_SKIP)) > 0) printf "%s\tskip\t%d\t%s\n", INVENTORY, n, t
  inv_cmp()
}

# A comparison statement with exactly one comparison operator and no && || ;
# the Go `if got != 3 {` and the bash `[ "$output" = "3" ]` forms. The masked
# line gates, the raw line gives the sides; inv_eq keeps only a literal side.
function inv_cmp(    m, n, l, r) {
  m = masked
  if (LEXER == "go") {
    if (m !~ /^[[:space:]]*if[[:space:]].*\{[[:space:]]*$/ || m ~ /&&|\|\||;/) return
    if ((n = gsub(/[!=]=/, "&", m)) != 1 || !match(m, /[!=]=/)) return
    l = substr(raw, 1, RSTART - 1); r = substr(raw, RSTART + RLENGTH)
    sub(/^[[:space:]]*if[[:space:]]+/, "", l); sub(/\{[[:space:]]*$/, "", r)
  } else if (LEXER == "bash") {
    if (m !~ /^[[:space:]]*\[\[?[[:space:]].*[[:space:]]\]\]?[[:space:]]*$/ || m ~ /&&|\|\||;/) return
    if ((n = gsub(/[[:space:]](==?|!=|-eq|-ne)[[:space:]]/, "&", m)) != 1 || !match(m, /[[:space:]](==?|!=|-eq|-ne)[[:space:]]/)) return
    l = substr(raw, 1, RSTART - 1); r = substr(raw, RSTART + RLENGTH)
    sub(/^[[:space:]]*\[\[?[[:space:]]+/, "", l); sub(/[[:space:]]+\]\]?[[:space:]]*$/, "", r)
  } else return
  inv_eq(l, r)
}

# An equality whose one side is a literal: the other side, then the literal.
function inv_eq(a, b) {
  if (!INVENTORY) return
  a = trim(a); b = trim(b)
  if (is_lit(b) && !is_lit(a)) printf "%s\texpect\t%s\t%s\n", INVENTORY, norm(a), norm(b)
  else if (is_lit(a) && !is_lit(b)) printf "%s\texpect\t%s\t%s\n", INVENTORY, norm(b), norm(a)
}

# ---------------------------------------------------------------------------
# CF2 — recomputed expectation (self-identical actual/expected), line-scoped.
# The masked line gates (no findings from comments or strings); the raw line
# is what the expressions are read from.
# ---------------------------------------------------------------------------

# The length of a Python line before its trailing # comment, so an annotation
# on the assert line stays out of the compared sides.
function py_code_len(s,    i, n, c, q) {
  n = length(s); q = ""
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (q != "") { if (c == "\\") i++; else if (c == q) q = "" }
    else if (c == "'" || c == "\"") q = c
    else if (c == "#") return i - 1
  }
  return n
}

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
      inv_eq(a, b)
      expr = norm(a)
      if (expr != "" && expr == norm(b)) {
        emit(tkind, "recomputed-expectation", FNR, RW_NAME[i] "(" expr ") compared to itself")
        return
      }
      if (const_check(a, b, tkind) || derived_check(a, b, tkind)) return
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
      inv_eq(SW1, SW2)
      expr = norm(SW1)
      if (expr != "" && expr == norm(SW2)) {
        emit(tkind, "recomputed-expectation", FNR, fn " " expr " " expr)
        return
      }
      if (const_check(SW1, SW2, tkind)) return
      continue
    }
    while (substr(raw_line, m, 1) ~ /[[:space:]]/) m++
    if (!extract_parens(raw_line, m)) continue
    if (!split_top_comma(EXTRACT)) continue
    a = SPLIT1; b = SPLIT2
    if (split_top_comma(b)) b = SPLIT1  # drop trailing message/args
    inv_eq(a, b)
    expr = norm(a)
    if (expr != "" && expr == norm(b)) {
      emit(tkind, "recomputed-expectation", FNR, fn "(" expr ", " expr ")")
      return
    }
    if (const_check(a, b, tkind) || derived_check(a, b, tkind)) return
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
    inv_eq(a, b)
    expr = unparen(norm(a))
    if (expr != "" && expr == unparen(norm(b))) {
      emit(tkind, "recomputed-expectation", FNR, expr " | " PIPE[i] " " expr)
      return
    }
    if (const_check(a, b, tkind) || derived_check(a, b, tkind)) return
  }
  # python assert EXPR == EXPR: the statement is language syntax, not adapter data
  if (LEXER == "python" && masked_line ~ /^[[:space:]]*assert[[:space:]]/) {
    rest = substr(raw_line, 1, py_code_len(raw_line))
    sub(/^[[:space:]]*assert[[:space:]]+/, "", rest)
    if (split_top_comma(rest)) rest = SPLIT1  # drop ", msg"
    if (split_top_eq(rest)) {
      inv_eq(EQL, EQR)
      expr = norm(EQL)
      if (expr != "" && expr == norm(EQR)) {
        emit(tkind, "recomputed-expectation", FNR, "assert " expr " == " expr)
      } else if (!const_check(EQL, EQR, tkind)) derived_check(EQL, EQR, tkind)
    }
  }
}

# ---------------------------------------------------------------------------
# Change detectors. rule-constant-restatement: an equality whose one side is a
# constant (SCREAMING_SNAKE, bare or at the end of a member access, no call)
# and whose other side is a literal. Shell variables are uppercase whether
# constant or computed, so a shell name counts only when nothing in the file
# assigned it earlier: it came from a sourced file. "Testing the fixture"
# (js, python): the subject's root is bound to a literal in the same block
# and the block calls nothing but assertions; judged when the block closes.
# ---------------------------------------------------------------------------

function is_lit(s) {
  if (s ~ /^-?[0-9][0-9_]*(\.[0-9]+)?$/ || s ~ /^(true|false|null|undefined|None|True|False)$/) return 1
  # A shell helper may take a message first; a spaced string is that message.
  if (SHELL_LEX && s ~ /[[:space:]]/) return 0
  if (s ~ /^'[^']*'$/ || s ~ /^"[^"$\\]*"$/ || s ~ /^`[^`$]*`$/) return 1
  return SHELL_LEX && s ~ /^[A-Za-z0-9_.,:\/+-]+$/
}

function is_const(s,    name) {
  if (SHELL_LEX) {
    name = s
    gsub(/^"|"$/, "", name)
    if (name !~ /^\$(\{[A-Z][A-Z0-9_]*[A-Z0-9]\}|[A-Z][A-Z0-9_]*[A-Z0-9])$/) return 0
    gsub(/[${}]/, "", name)
    return !(name in SH_SET) && name !~ /^BATS_/
  }
  return s ~ /^([A-Za-z_$][A-Za-z0-9_$]*\.)*[A-Z][A-Z0-9_]*[A-Z0-9]$/ && s !~ /(^|\.)env\./
}

function const_check(a, b, tkind,    x, y) {
  if (!LINE_IN_TEST) return 0
  x = trim(a); y = trim(b)
  if (is_lit(x) && !is_lit(y)) { x = y; y = trim(a) }
  if (!is_lit(y) || x == "") return 0
  # No act step before the assertion: a call, or in shell any command after the
  # last source line, may be what gave the uppercase name its value.
  if (is_const(x)) {
    if (SHELL_LEX ? SH_ACT : !g8_no_calls()) return 0
    emit(tkind, "constant-restatement", FNR, "constant " x " compared to the literal " y)
    return 1
  }
  # A path rooted in a plain identifier, no call anywhere in it.
  if ((LEXER == "js" || LEXER == "python") && x ~ /^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*|\[[^]()]*\])*$/)
    G8_CAND = G8_CAND FNR "\t" tkind "\t" x "\t" y "\n"
  return 0
}

# A binding of a name to a literal, for the fixture variant.
function g8_bind(m, r,    re) {
  if (LEXER == "js") re = "^[[:space:]]*(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*([{['\"`0-9-]|true|false|null)"
  else re = "^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*([{['\"0-9-]|True|False|None)"
  if (r !~ re) return
  sub(/^[[:space:]]*((const|let|var)[[:space:]]+)?/, "", m)
  match(m, /^[A-Za-z_$][A-Za-z0-9_$]*/)
  G8_BOUND = G8_BOUND " " substr(m, 1, RLENGTH) " "
}

# 1 when every call in the block body, the test-start line aside, is an
# assertion: expect, assert*, a to* matcher, or node:assert's bare helpers,
# or an import. Run mid-block, it covers the lines read so far, this one included.
function g8_no_calls(    rest, n, lines, i, s, name) {
  n = split(block_masked, lines, "\n")
  for (i = 2; i <= n; i++) {
    s = lines[i]
    while (match(s, /[A-Za-z_$][A-Za-z0-9_$.]*[[:space:]]*\(/)) {
      name = substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
      gsub(/[[:space:](]/, "", name)
      if (name ~ /^(if|for|while|switch|catch|function|return|typeof|await|and|or|not|in|assert|elif)$/) continue
      sub(/^.*\./, "", name)
      if (name !~ /^(expect|assert[A-Za-z_]*|to[A-Z][A-Za-z]*|strictEqual|deepStrictEqual|deepEqual|equal|notEqual|ok|require|import)$/) return 0
    }
  }
  return 1
}

function g8_eval(    n, recs, i, f, root) {
  if (G8_CAND == "" || G8_BOUND == "" || !g8_no_calls()) return
  n = split(G8_CAND, recs, "\n")
  for (i = 1; i < n; i++) {
    split(recs[i], f, "\t")
    root = f[3]
    sub(/[.[].*$/, "", root)
    if (index(G8_BOUND, " " root " "))
      emit(f[2], "constant-restatement", f[1], root " is a literal bound in the test and " f[3] " is compared to the literal " f[4] " with no code under test called")
  }
}

# Shell names assigned so far in the file: bash NAME=, local/export/readonly/
# declare NAME=, read NAME, for NAME in; PowerShell $NAME =.
function sh_assign(m,    s, name) {
  s = m
  while (match(s, /(^|[[:space:];&|(])(local|export|readonly|declare|typeset)?[[:space:]]*(-[A-Za-z]+[[:space:]]+)*[A-Za-z_][A-Za-z0-9_]*\+?=/)) {
    name = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    sub(/\+?=$/, "", name)
    sub(/^.*[^A-Za-z0-9_]/, "", name)
    SH_SET[name] = 1
  }
  if (match(m, /(^|[[:space:];&|])(read|for)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*[A-Za-z_][A-Za-z0-9_[:space:]]*/)) {
    s = substr(m, RSTART, RLENGTH)
    sub(/^[^A-Za-z]*(read|for)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*/, "", s)
    while (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) {
      SH_SET[substr(s, RSTART, RLENGTH)] = 1
      s = substr(s, RSTART + RLENGTH)
    }
  }
  if (LEXER == "pwsh" && match(m, /^[[:space:]]*\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[^=]/)) {
    name = substr(m, RSTART, RLENGTH)
    gsub(/[^A-Za-z0-9_]/, "", name)
    SH_SET[name] = 1
  }
}

# SH_ACT: a command ran in the test since its last source line, so a name it
# reads may hold that command's output. Settings, declarations without a
# substitution, [ ] tests, assertions, block keywords and the bodies of
# functions the test defines run nothing under test.
function sh_act_scan(m,    s, n, seg, i) {
  s = m
  sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
  if (SH_FN) { SH_FN += brace_delta(m); return }
  if (s == "" || FNR == block_line) return
  if (s ~ /^(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_:]*[[:space:]]*\([[:space:]]*\)[[:space:]]*\{?/ || s ~ /^function[[:space:]]/) {
    SH_FN = brace_delta(m)
    return
  }
  # One command at a time: source lib.sh; parse_args ...; assert_equal ...
  gsub(/&&|\|\|/, ";", s)
  n = split(s, seg, ";")
  for (i = 1; i <= n; i++) sh_act_cmd(seg[i])
}

function sh_act_cmd(s,    w, w2) {
  sub(/^[[:space:]]+/, "", s)
  if (s == "") return
  match(s, /^[^[:space:];&|]+/); w = substr(s, 1, RLENGTH)
  w2 = substr(s, RLENGTH + 1); sub(/^[[:space:]]+/, "", w2); sub(/[[:space:]].*/, "", w2)
  if (w ~ /^(source|\.|load)$/) { SH_ACT = 0; return }
  if (w ~ /^(if|elif|while|until|!)$/) w = w2
  if (w ~ /^(set|shopt|\[|\[\[|test|then|else|fi|do|done|esac|\{|\}|\(|\)|true|:)$/ || has(w, R_ANY)) return
  if (w ~ /^(local|export|readonly|declare|typeset)$/ || w ~ /^[A-Za-z_][A-Za-z0-9_]*\+?=/)
    if (s !~ /\$\(|`/) return
  SH_ACT = 1
}

# Whole-file bash facts the shell forms depend on: set -e (a failing [ ] then
# exits), a sourced helper (which may set it), a cd (a relative path no longer
# resolves against the start directory), and names assigned from mktemp or a
# temp directory (never a source path).
function sh_file_facts(    name, rhs, v) {
  if (masked ~ /(^|[[:space:];&|])set[[:space:]]+(-[A-Za-z]*e[A-Za-z]*|-o[[:space:]]+errexit)([[:space:]]|$)/ ||
      (FNR == 1 && raw ~ /^#!.*[[:space:]]-[A-Za-z]*e/)) SET_E = 1
  if (masked ~ /(^|[[:space:];&|])(source|\.)[[:space:]]/) SOURCED = 1
  if (masked ~ /(^|[[:space:];&|])(cd|pushd)[[:space:]]/) SH_CD = 1
  if (match(raw, /^[[:space:]]*((local|export|readonly|declare)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/)) {
    name = substr(raw, RSTART, RLENGTH - 1)
    sub(/^.*[^A-Za-z0-9_]/, "", name)
    rhs = substr(raw, RSTART + RLENGTH)
    if (rhs ~ /mktemp|TMP|TEMP|[Tt]mp|[Tt]emp/) SH_TMP[name] = 1
    else if (match(rhs, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
      v = substr(rhs, RSTART, RLENGTH)
      gsub(/[${]/, "", v)
      if (v in SH_TMP) SH_TMP[name] = 1
    }
  }
}

# ---------------------------------------------------------------------------
# rule-inert-assertion: a statement that looks like an assertion and never
# asserts. The adapter's assertion.async (never awaited) and assertion.inert
# forms match a statement start; the language forms live here: the Python
# tuple assert, bats run and !, a harness [ ] whose status nothing reads, and
# for go the if statement joined onto one line.
# ---------------------------------------------------------------------------

function snippet(r) {
  sub(/^[[:space:]]+/, "", r); sub(/[[:space:]]+$/, "", r)
  return length(r) > 60 ? substr(r, 1, 57) "..." : r
}

function line_kind() { return (raw ~ R_EXEMPT || prev_raw ~ R_EXEMPT) ? "X" : "F" }

# A statement starts on this line unless the code before it leaves an
# expression open (an operator, an opener, a comma, a line continuation).
function stmt_start(    p) {
  if (LEXER == "python") return bracket_depth <= 0 && prev_code !~ /\\[[:space:]]*$/
  p = prev_code
  sub(/[[:space:]]+$/, "", p)
  if (p ~ /[-+*\/%=<>!&|?:,(\[.\\`]$/) return 0
  return p !~ /(^|[^A-Za-z0-9_$])(await|return|yield|void)$/
}

# The code line as seen for stmt_start: masking blanks a string, so a line
# ending in one would read as ending in the "=" before it. A closing quote in
# the raw text stands in for the masked string; a comment stays blank.
function code_tail(m, r,    i, c) {
  for (i = length(r); i > 0; i--) {
    c = substr(m, i, 1)
    if (c !~ /[[:space:]]/) return m
    c = substr(r, i, 1)
    if (c == "\"" || c == "'" || c == "`") return substr(m, 1, i - 1) "\""
  }
  return m
}

function py_assert_inert(r,    rest) {
  rest = r
  sub(/^[[:space:]]*assert[[:space:]]*/, "", rest)
  if (has(rest, R_INERT)) return "assert of a mock attribute is always true"
  if (substr(rest, 1, 1) == "(" && extract_parens(rest, 1) && split_top_comma(EXTRACT) &&
      substr(rest, EXTEND + 1) ~ /^[[:space:]]*(#.*)?$/)
    return "assert of a parenthesized tuple is always true"
  return ""
}

# bats: `run cmd` leaves the status in $status, so a run nothing checks before
# the next run or the end of the test passes whatever cmd did; `! cmd` fails
# the test only as its last command. Harness (file model): a [ ] test on its
# own line whose status the next line does not read, in a file with no set -e
# and no sourced helper that might set it.
function sh_inert(s, r) {
  if (MODEL == "file") {
    if (s == "" || s ~ /^(fi|done|esac|else|elif|then|do|\}|\)|;;)/) { if (s != "") BRK_PEND = ""; return }
    if (BRK_PEND != "" && r !~ /\$\?/) BRK_OUT = BRK_OUT BRK_PEND
    BRK_PEND = ""
    if (s ~ /^\[\[?[[:space:]][^;&|]*[[:space:]]\]\]?[[:space:]]*;?$/)
      BRK_PEND = FNR "\t" line_kind() "\t" snippet(r) "\n"
    return
  }
  if (s != "" && s !~ /^(fi|done|esac|\}|\)|;;)/ && BANG_PEND) {
    emit(BANG_KIND, "inert-assertion", BANG_PEND, "a ! command that is not the test's last line never fails it: " BANG_SNIP)
    BANG_PEND = 0
  }
  if (s ~ /^run[[:space:]]/ && s !~ /^run[[:space:]]+(--?[A-Za-z-]+[[:space:]]+)*(!|-[0-9])/) {
    if (RUN_PEND) emit(RUN_KIND, "inert-assertion", RUN_PEND, "run result never checked: " RUN_SNIP)
    RUN_PEND = FNR; RUN_KIND = line_kind(); RUN_SNIP = snippet(r)
    r = substr(r, index(r, "run") + 3)
  } else if (s ~ /^run[[:space:]]/) {
    if (RUN_PEND) emit(RUN_KIND, "inert-assertion", RUN_PEND, "run result never checked: " RUN_SNIP)
    RUN_PEND = 0
  }
  if (RUN_PEND && r ~ /\$\{?(status|output|lines|stderr|stderr_lines)([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])(assert|refute)[A-Za-z_]*/) RUN_PEND = 0
  if (s ~ /^![[:space:]]/) { BANG_PEND = FNR; BANG_KIND = line_kind(); BANG_SNIP = snippet(r) }
}

# Flushed as the block closes: a pending run or harness [ ] is decided there.
function inert_close(    n, recs, i, f) {
  if (has(block_masked, R_BODY_SKIP)) RUN_PEND = 0
  if (RUN_PEND) emit(RUN_KIND, "inert-assertion", RUN_PEND, "run result never checked: " RUN_SNIP)
  if (PS_PEND) emit(PS_KIND, "inert-assertion", PS_PEND, PS_DET)
  # A ! command on the test's last line is its assertion.
  BANG_LAST = BANG_PEND
  RUN_PEND = BANG_PEND = PS_PEND = 0
  if (!SET_E && !SOURCED && BRK_OUT != "") {
    n = split(BRK_OUT, recs, "\n")
    for (i = 1; i < n; i++) {
      split(recs[i], f, "\t")
      emit(f[2], "inert-assertion", f[1], "a [ ] test whose status nothing reads, with no set -e, never fails the script: " f[3])
    }
  }
  BRK_OUT = BRK_PEND = ""
}

# go: an if statement is joined onto one line (at most 30) before the inert
# forms are matched, so a multi-line branch holding only t.Log reads whole.
function go_inert(s, m) {
  if (GO_IF == 0) {
    if (s !~ /^if[[:space:]]/) return
    GO_IF = FNR; GO_KIND = line_kind(); GO_BUF = s; GO_D = brace_delta(m); GO_N = 0; GO_S0 = OR_S0
  } else {
    GO_BUF = GO_BUF " " s; GO_D += brace_delta(m)
  }
  if (GO_D > 0 && ++GO_N <= 30) return
  if (GO_D <= 0 && has(GO_BUF, R_INERT) && GO_BUF !~ /(^|[^A-Za-z0-9_])nil([^A-Za-z0-9_]|$)/)
    emit(GO_KIND, "inert-assertion", GO_IF, "an if branch that only logs never fails the test: " snippet(GO_BUF))
  # A nil check whose branch only fails is a weak oracle: its failing calls
  # were counted strong line by line, and are taken back here.
  if (GO_D <= 0 && has(GO_BUF, R_WEAK)) {
    OR_S = GO_S0
    if (!OR_W++) { OR_WLINE = GO_IF; OR_WSNIP = snippet(GO_BUF) }
  }
  GO_IF = 0
}

function inert_scan(m, r,    s, d) {
  s = m
  sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
  if (LEXER == "bash") { sh_inert(s, r); return }
  if (LEXER == "go") { if (GO_IF || stmt_start()) go_inert(s, m); return }
  # A PowerShell 7 line opening with a pipe continues the one before it.
  if (PS_PEND && s != "") {
    if (s !~ /^\|/) emit(PS_KIND, "inert-assertion", PS_PEND, PS_DET)
    PS_PEND = 0
  }
  if (s == "" || !stmt_start()) return
  # A Pester script block nested in the test (a ParameterFilter, a
  # Where-Object) returns its bare comparison; only the It body discards it.
  if (LEXER == "pwsh" && depth != 1) return
  d = ""
  if (has(s, R_ASYNC)) d = "an async assertion nothing awaits never runs before the test ends"
  else if (has(s, R_INERT)) d = "the statement looks like an assertion and asserts nothing"
  else if (LEXER == "python" && s ~ /^assert[[:space:](]/) d = py_assert_inert(r)
  if (d == "") return
  if (LEXER == "pwsh") { PS_PEND = FNR; PS_KIND = line_kind(); PS_DET = d ": " snippet(r) }
  else emit(line_kind(), "inert-assertion", FNR, d ": " snippet(r))
}

# ---------------------------------------------------------------------------
# rule-source-text-read candidates: a file read whose path is a static
# literal, optionally joined onto the test's own directory or the repository
# root. A path from a variable, a glob or a walk is never a candidate, and
# neither is a temp, fixture or testdata path.
# ---------------------------------------------------------------------------

function unquote(s) {
  if (s ~ /^@?"[^"]*"$/) { sub(/^@?"/, "", s); sub(/"$/, "", s) }
  else if (s ~ /^'[^']*'$/ || s ~ /^`[^`$]*`$/) s = substr(s, 2, length(s) - 2)
  else return ""
  return s
}

# The literal path an argument list names, or "".
function arg_path(args,    first, p) {
  first = split_top_comma(args) ? trim(SPLIT1) : trim(args)
  if (unquote(first) != "") return unquote(first)
  # new URL('lit', import.meta.url)
  if (first ~ /^new[[:space:]]+URL[[:space:]]*\(/ && index(first, "import.meta.url")) {
    p = index(first, "(")
    if (extract_parens(first, p) && split_top_comma(EXTRACT)) return unquote(trim(SPLIT1))
    return ""
  }
  # join / resolve / Path.Combine / filepath.Join over a base and literals
  if (first ~ /^([A-Za-z_]+\.)?(resolve|join|Join|Combine)[[:space:]]*\(/) {
    p = index(first, "(")
    if (!extract_parens(first, p)) return ""
    return join_literals(EXTRACT)
  }
  return ""
}

function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }

# Literal parts joined with "/", after an optional leading base that names the
# test's directory (__dirname, import.meta.dirname).
function join_literals(args,    out, part, more) {
  out = ""
  for (;;) {
    more = split_top_comma(args)
    part = trim(more ? SPLIT1 : args)
    if (out == "" && part ~ /^(__dirname|import\.meta\.dirname)$/) part = ""
    else {
      part = unquote(part)
      if (part == "") return ""
    }
    if (part != "") out = out (out == "" ? "" : "/") part
    if (!more) break
    args = SPLIT2
  }
  return out
}

# A read counts only when the test then searches the text (indexOf, toContain,
# `in`, Contains, -match, grep) and nothing parses or executes it: a test that
# compares a generated file whole, walks a syntax tree or runs the script is
# exercising it. Candidates wait in SRC_PEND until the block closes.
function src_flush(    blk, s, n, recs, i, f) {
  blk = block_masked
  if (index(RULES_OFF, "|source-text-read|")) { SRC_PEND = ""; return }
  if (LEXER == "js") s = "\\.[[:space:]]*(indexOf|lastIndexOf|includes|match|matchAll|search|startsWith|endsWith|test)[[:space:]]*\\(|to(Contain|Match)|stringContaining|(^|[^A-Za-z0-9_$.])(match|doesNotMatch)[[:space:]]*\\("
  else if (LEXER == "python") s = "\\.[[:space:]]*(index|rindex|find|rfind|count|startswith|endswith)[[:space:]]*\\(|(^|[^A-Za-z0-9_])re[[:space:]]*\\.[[:space:]]*(search|match|findall|fullmatch|finditer)|assert(Not)?(In|Regex)|(^|[[:space:]])assert[[:space:]].*[[:space:]]in[[:space:]]"
  else if (LEXER == "cs") s = "Contain|IndexOf|StartsWith|EndsWith|Regex|StringAssert|Does[[:space:]]*\\.[[:space:]]*Match"
  else if (LEXER == "go") s = "(strings|bytes)[[:space:]]*\\.[[:space:]]*(Contains|Index|HasPrefix|HasSuffix|Count)|regexp[[:space:]]*\\."
  else if (LEXER == "pwsh") { blk = tolower(blk); s = "-(not)?(match|like|contains)|-(belike|contain)|select-string|\\.(contains|indexof)[[:space:]]*\\(" }
  else s = "(^|[^A-Za-z0-9_-])(grep|egrep|fgrep)([[:space:]]|$)|=~"
  if (blk ~ s && blk !~ /ast[[:space:]]*\.[[:space:]]*parse|(^|[^A-Za-z0-9_$.])(compile|exec|eval)[[:space:]]*\(|runIn(New|This)?Context|vm[[:space:]]*\.[[:space:]]*(run|compileFunction|Script)|new[[:space:]]+Function|SyntaxTree[[:space:]]*\.[[:space:]]*ParseText|parser[[:space:]]*\.[[:space:]]*Parse|invoke-expression|scriptblock\]::create/) {
    n = split(SRC_PEND, recs, "\n")
    for (i = 1; i < n; i++) {
      split(recs[i], f, "\t")
      emit("S", f[1], f[2], f[3])
    }
  }
  SRC_PEND = ""
}

function src_emit(path) {
  gsub(/\\/, "/", path)
  sub(/^\.\//, "", path)
  if (path == "" || path ~ /[*?[$]/ || path ~ /^\//) return
  if (tolower(path) ~ /(^|\/)(tmp|temp|fixtures?|testdata|__fixtures__|__testfixtures__|__snapshots__|snapshots?)(\/|$)/) return
  if (path !~ /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|py|cs|razor|go|sh|bash|ps1|psm1|vue|svelte)$/) return
  SRC_PEND = SRC_PEND line_kind() "\t" FNR "\t" path "\n"
}

# A shell word naming a path: a literal, or one joined onto the test's own
# directory ($(dirname ...), ${BASH_SOURCE%/*}, $BATS_TEST_DIRNAME) or a
# directory variable that names the repository or a script directory and was
# never assigned from mktemp or a temp variable.
function sh_path(w,    v) {
  if (w ~ /^"/) { sub(/^"/, "", w); sub(/"$/, "", w) }
  else if (w ~ /^'[^']*'$/) return substr(w, 2, length(w) - 2)
  if (w ~ /^\$\(dirname[^)]*\)\//) sub(/^\$\(dirname[^)]*\)\//, "", w)
  else if (w ~ /^\$\{BASH_SOURCE(\[0\])?%\/\*\}\//) sub(/^[^}]*\}\//, "", w)
  else if (match(w, /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\//)) {
    v = substr(w, 1, RLENGTH - 1)
    gsub(/[${}]/, "", v)
    if (v in SH_TMP || v !~ /^(BATS_TEST_DIRNAME|[A-Z_]*(ROOT|DIR|REPO|HERE))$/ ||
        v ~ /TMP|TEMP|WORK|FIX|SANDBOX|SCRATCH|OUT|CACHE|DATA|HOME|CASE|STUB|MOCK|FAKE|BIN/) return ""
    w = substr(w, RLENGTH + 1)
  } else if (SH_CD) return ""
  return w ~ /[$`]/ ? "" : w
}

function src_scan_sh(m, r,    s, rest, cmd, i, n, skip_first, w, prev) {
  s = m
  while (match(s, /(^|[;&|(!]|(^|[[:space:]])(if|then|while|until|elif|do|run))[[:space:]]*(cat|grep|sed|awk|head)[[:space:]]/)) {
    rest = substr(s, RSTART + RLENGTH)
    cmd = substr(s, RSTART, RLENGTH)
    s = rest
    i = length(m) - length(rest) + 1
    n = length(r)
    skip_first = cmd ~ /(grep|sed|awk)[[:space:]]$/
    prev = ""
    while (i <= n) {
      while (substr(r, i, 1) ~ /[[:space:]]/) i++
      if (i > n || substr(r, i, 1) ~ /[|;&><)]/) break
      i = shell_word(r, i); w = SW
      if (w ~ /^-/) {
        # -e PATTERN / -f PROGRAM: the pattern word is given, so every
        # operand after it is a file; the word after -f is a program.
        if (w ~ /^-(e|f)$|^--(file|regexp)$/) skip_first = 0
        prev = w
        continue
      }
      if (prev ~ /^-(e|f)$|^--(file|regexp)$/) { prev = ""; continue }
      prev = ""
      if (skip_first) { skip_first = 0; continue }
      w = sh_path(w)
      if (w != "") src_emit(w)
    }
  }
}

function src_scan(m, r,    p, args, low, w) {
  if (m ~ /(^|[^A-Za-z0-9_])(find|glob|readdir|readdirSync|walk|Walk|WalkDir|iglob|rglob|GetFiles|EnumerateFiles)[[:space:]]*[( ]/ ||
      tolower(m) ~ /get-childitem|mktemp/) return
  if (LEXER == "bash") { src_scan_sh(m, r); return }
  if (LEXER == "js" && match(m, /(^|[^A-Za-z0-9_$])readFile(Sync)?[[:space:]]*\(/)) {
    p = RSTART + RLENGTH - 1
    if (extract_parens(r, p)) src_emit(arg_path(EXTRACT))
  } else if (LEXER == "python" && match(m, /(^|[^A-Za-z0-9_.])(open|Path)[[:space:]]*\(/)) {
    p = RSTART + RLENGTH - 1
    if (!extract_parens(r, p)) return
    args = EXTRACT
    if (substr(m, RSTART, RLENGTH) ~ /Path/ && substr(m, EXTEND + 1) !~ /^[[:space:]]*\.[[:space:]]*read_(text|bytes)[[:space:]]*\(/) return
    if (split_top_comma(args)) {
      if (trim(SPLIT2) !~ /^['"]r[bt]?['"]/ && SPLIT2 !~ /^[[:space:]]*encoding[[:space:]]*=/) return
      args = SPLIT1
    }
    src_emit(unquote(trim(args)))
  } else if (LEXER == "cs" && match(m, /File[[:space:]]*\.[[:space:]]*ReadAll(Text|Lines|Bytes)(Async)?[[:space:]]*\(/)) {
    p = RSTART + RLENGTH - 1
    if (extract_parens(r, p)) src_emit(arg_path(EXTRACT))
  } else if (LEXER == "go" && match(m, /(os|ioutil)[[:space:]]*\.[[:space:]]*ReadFile[[:space:]]*\(/)) {
    p = RSTART + RLENGTH - 1
    if (extract_parens(r, p)) src_emit(arg_path(EXTRACT))
  } else if (LEXER == "pwsh" && match(tolower(m), /(^|[^a-z0-9_-])get-content[[:space:]]/)) {
    p = RSTART + RLENGTH
    shell_words(r, p)
    w = SW1
    if (tolower(w) ~ /^-(literal)?path$/) w = SW2
    if (w ~ /^"\$PSScriptRoot[\/\\]/) { sub(/^"\$PSScriptRoot[\/\\]/, "", w); sub(/"$/, "", w); if (w ~ /[$`]/) w = "" }
    else if (w ~ /^\(Join-Path[[:space:]]/) {
      low = w; sub(/^\(Join-Path[[:space:]]+\$PSScriptRoot[[:space:]]+/, "", low)
      w = low == w ? "" : unquote(trim(substr(low, 1, length(low) - 1)))
    } else w = unquote(w)
    src_emit(w)
  }
}

# ---------------------------------------------------------------------------
# Oracle strength: every assertion line of a block is strong, weak (only an
# assertion.weak call) or a snapshot (only a snapshot call). rule-weak-oracle
# and rule-snapshot-only fire when a block holds nothing but that kind. The
# adapter entries match whole calls over the line with strings standing as
# `_`, so a matcher argument (toThrow('boom')) is never read as absent.
# ---------------------------------------------------------------------------

function fill(m, r,    i, n, out, c) {
  if (m == r) return m
  out = ""; n = length(m)
  for (i = 1; i <= n; i++) {
    c = substr(m, i, 1)
    if (c == " " && substr(r, i, 1) != " ") c = "_"
    out = out c
  }
  return out
}

# 1 when the line's only assertions are calls re covers.
function only_calls(m, r, re,    f) {
  if (!has(m, re)) return 0
  f = fill(m, r)
  if (!has(f, re)) return 0
  gsub(re, "", f)
  return !has(f, R_ANY) && !has(f, R_MOCKA)
}

function oracle_line(m, r) {
  if (!has(m, R_ANY) && !has(m, R_MOCKA)) return
  # go: the nil check is an if statement, judged whole in go_inert.
  if (LEXER != "go" && only_calls(m, r, R_WEAK)) { if (!OR_W++) { OR_WLINE = FNR; OR_WSNIP = snippet(r) }; return }
  if (only_calls(m, r, R_SNAP) && snap_ok(m)) { if (!OR_P++) OR_PLINE = FNR; return }
  OR_S++
}

# A snapshot call needs its library in reach: in C#, Verify's (CS_VERIFY); in
# Python, syrupy's snapshot fixture, which is a parameter of the test.
function snap_ok(m) {
  if (LEXER == "cs") return CS_VERIFY
  if (LEXER == "python" && m ~ /(^|[^A-Za-z0-9_.])snapshot([^A-Za-z0-9_]|$)/) return SIG ~ /[(,][[:space:]]*snapshot[[:space:]]*[,:)=]/
  return 1
}

# ---------------------------------------------------------------------------
# rule-conditional-assertion: every assertion of the block sits inside an if,
# a catch or a loop over a value the test computed, so some path asserts
# nothing. A call that fails the test outright (assertion.fail) is the
# assertion an if or catch exists to make, and counts as conditional only
# inside such a loop. A loop over a literal table, a range or a name bound
# outside the test is a table-driven test and asserts on every row.
# ---------------------------------------------------------------------------

# The name an assignment statement binds, left in AS_NAME with its raw
# right-hand side in AS_RHS; 0 when s (masked, leading blanks removed) is no
# declaration. A plain reassignment sets AS_NAME with AS_RHS "".
function assign_of(s, rl,    re, p) {
  AS_NAME = AS_RHS = ""
  if (LEXER == "js") re = "^(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(:[^=]*)?="
  else if (LEXER == "python") re = "^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(:[^=]*)?="
  else if (LEXER == "cs") re = "^(var|[A-Za-z_][A-Za-z0-9_<>,.?]*(\\[\\])?)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*="
  else if (LEXER == "go") re = "^(var[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[^=]*=|[A-Za-z_][A-Za-z0-9_]*([[:space:]]*,[[:space:]]*[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*:=)"
  else if (LEXER == "pwsh") re = "^\\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]*="
  else return 0
  if (match(s, re) && substr(s, RLENGTH + 1, 1) !~ /[=>]/) {
    p = substr(s, 1, RLENGTH)
    AS_RHS = trim(substr(rl, RLENGTH + 1))
    sub(/;[[:space:]]*$/, "", AS_RHS)
    if (LEXER == "cs") { sub(/[[:space:]]*=$/, "", p); sub(/^.*[^A-Za-z0-9_]/, "", p) }
    else { sub(/^(const|let|var)[[:space:]]+/, "", p); sub(/^\$/, "", p); match(p, /^[A-Za-z_$][A-Za-z0-9_$]*/); p = substr(p, 1, RLENGTH) }
  } else if (match(s, /^\$?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[-+*\/%]?=/) && substr(s, RLENGTH + 1, 1) !~ /[=>]/) {
    p = substr(s, 1, RLENGTH); gsub(/[^A-Za-z0-9_]/, "", p)
  } else return 0
  AS_NAME = LEXER == "pwsh" ? tolower(p) : p
  return 1
}

function literal_rhs(v) {
  if (LEXER == "js") return v ~ /^([[{'"`0-9-]|(true|false|null|undefined)([^A-Za-z0-9_$]|$)|new[[:space:]]+(Array|Set|Map)[^A-Za-z0-9_$])/
  if (LEXER == "python") return v ~ /^([[({'"0-9-]|[rbfu]['"]|(True|False|None)([^A-Za-z0-9_]|$)|range[[:space:]]*\()/
  if (LEXER == "cs") return v ~ /^([[{"'0-9-]|@"|\$"|new[[:space:]]*\[[[:space:]]*\]|new[[:space:]]+[A-Za-z0-9_.<>,]+[[:space:]]*(\[[[:space:]]*\])?[[:space:]]*(\([[:space:]]*\))?[[:space:]]*\{|(true|false|null)([^A-Za-z0-9_]|$)|Enumerable[[:space:]]*\.[[:space:]]*Range)/
  if (LEXER == "go") return v ~ /^(\[|map\[|&?[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\{|["'`0-9-]|(true|false|nil)([^A-Za-z0-9_]|$))/
  return tolower(v) ~ /^(@\(|@\{|['"0-9-]|\$(true|false|null)([^a-z0-9_]|$)|\[)/
}

# Per statement: which names the test bound to a literal and which to a
# computed value (a loop over the latter is a loop over a result), and the
# right-hand side of each for rule-recomputed-derived.
function bind_scan(m, r,    s, rl) {
  s = m; sub(/^[[:space:]]+/, "", s)
  # Promise.all( with its argument on the next line.
  if (PM_NAME != "" && s != "") { if (mapped_literal(s)) RES[BID, PM_NAME] = "l"; PM_NAME = "" }
  if (LEXER == "python" ? bracket_depth > 0 : !stmt_start()) return
  rl = r; sub(/^[[:space:]]+/, "", rl)
  if (!assign_of(s, rl)) return
  DV_N[BID, AS_NAME]++
  DV_RHS[BID, AS_NAME] = AS_RHS
  if (AS_RHS != "") RES[BID, AS_NAME] = literal_rhs(AS_RHS) || mapped_literal(AS_RHS) ? "l" : "r"
  if (LEXER == "js" && AS_RHS ~ /Promise[[:space:]]*\.[[:space:]]*all(Settled)?[[:space:]]*\($/) PM_NAME = AS_NAME
}

# js: a map over a nonempty array literal, or over a name the test bound
# to one, optionally awaited through Promise.all, has one entry per literal
# element.
function mapped_literal(v,    e) {
  if (LEXER != "js") return 0
  e = v
  sub(/^(await[[:space:]]+)?(Promise[[:space:]]*\.[[:space:]]*all(Settled)?[[:space:]]*\([[:space:]]*)?/, "", e)
  if (e ~ /^\[[^]]*\][[:space:]]*\.[[:space:]]*map[[:space:]]*\(/) return e !~ /^\[[[:space:]]*\]/
  if (!match(e, /^[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*\.[[:space:]]*map[[:space:]]*\(/)) return 0
  sub(/[[:space:]]*\..*$/, "", e)
  return RES[BID, e] == "l"
}

function cr_push(k, l) {
  CR_N++; CR_L[CR_N] = l; CR_K[CR_N] = k
  if (k == "l") CR_LOOPS++; else CR_BR++
}

function cr_pop() {
  if (CR_K[CR_N] == "l") CR_LOOPS--; else CR_BR--
  CR_N--
}

# One assertion-bearing text, inside the open regions plus k.
function ca_class(t, k,    loops, br) {
  if (!has(t, R_ANY) && !has(t, R_MOCKA)) return
  loops = CR_LOOPS + (k == "l"); br = CR_BR + (k == "b")
  if (has(t, R_FAILC) ? loops > 0 : loops + br > 0) { if (!CA_IN++) { CA_LINE = FNR; CA_SNIP = snippet(raw) } }
  else CA_OUT++
}

# The loop kind when name (a root identifier) was computed in the test.
function loop_kind(name) {
  if (LEXER == "pwsh") name = tolower(name)
  return RES[BID, name] == "r" ? "l" : ""
}

function cond_brace(m,    cdb, s, k, low, pos, pre, post, e) {
  cdb = CD
  CD += brace_delta(m)
  s = m; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
  if (FNR == block_line || s == "") return
  while (CR_N > 0 && CR_L[CR_N] > cdb) cr_pop()
  if (COND_NEXT != "") {
    k = COND_NEXT; COND_NEXT = ""
    if (s !~ /^\{/) { ca_class(m, k); return }
    cr_push(k, cdb + 1)
  }
  k = ""; pos = 0
  low = LEXER == "pwsh" ? tolower(m) : m
  if (LEXER == "go") {
    if (match(m, /^[[:space:]]*for[[:space:]].*range[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
      e = substr(m, RSTART, RLENGTH); sub(/.*[[:space:]]/, "", e)
      if ((k = loop_kind(e)) != "") pos = RSTART
    }
  } else if (match(low, /^[[:space:]]*(\}[[:space:]]*)?(if|elseif|catch)([[:space:]]*[({]|[[:space:]]|$)/)) {
    k = "b"; pos = RSTART
  } else if (LEXER == "js" && match(m, /\.[[:space:]]*catch[[:space:]]*\(/)) {
    k = "b"; pos = RSTART
  } else if (LEXER == "js" && match(m, /^[[:space:]]*for[[:space:]]*\(.*[[:space:]](of|in)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$.]*[[:space:]]*\)/)) {
    e = substr(m, RSTART, RLENGTH); sub(/[[:space:]]*\)$/, "", e); sub(/.*[[:space:]]/, "", e); sub(/\..*/, "", e)
    if ((k = loop_kind(e)) != "") pos = RSTART
  } else if (LEXER == "js" && match(m, /[A-Za-z_$][A-Za-z0-9_$.]*[[:space:]]*\.[[:space:]]*forEach[[:space:]]*\(/)) {
    pos = RSTART; e = substr(m, RSTART, RLENGTH); sub(/[.[:space:]].*/, "", e)
    if ((k = loop_kind(e)) == "") pos = 0
  } else if (LEXER == "cs" && match(m, /^[[:space:]]*foreach[[:space:]]*\(.*[[:space:]]in[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*\)/)) {
    e = substr(m, RSTART, RLENGTH); sub(/[[:space:]]*\)$/, "", e); sub(/.*[[:space:]]/, "", e); sub(/\..*/, "", e)
    if ((k = loop_kind(e)) != "") pos = RSTART
  } else if (LEXER == "pwsh" && (match(low, /^[[:space:]]*foreach[[:space:]]*\([[:space:]]*\$[a-z_][a-z0-9_]*[[:space:]]+in[[:space:]]+\$[a-z_][a-z0-9_]*/) ||
             match(low, /\$[a-z_][a-z0-9_]*[[:space:]]*\|[[:space:]]*(foreach-object|%)[[:space:]]*\{/))) {
    pos = RSTART; e = substr(low, RSTART, RLENGTH)
    if (e ~ /^[[:space:]]*foreach/) sub(/.*\$/, "", e); else { sub(/^\$/, "", e); sub(/[^a-z0-9_].*/, "", e) }
    if ((k = loop_kind(e)) == "") pos = 0
  }
  if (k == "" || pos == 0) { ca_class(m, ""); return }
  pre = substr(m, 1, pos - 1); post = substr(m, pos)
  # "} catch (e) {": the brace closing the try belongs before the region.
  if (match(post, /^[[:space:]]*\}/)) { pre = pre substr(post, 1, RLENGTH); post = substr(post, RLENGTH + 1) }
  ca_class(pre, "")
  ca_class(post, k)
  if (brace_delta(post) > 0) cr_push(k, cdb + brace_delta(pre) + 1)
  # The body is the next statement: after a keyword's closed condition, or
  # inside a call (forEach, catch) whose parentheses are still open.
  else if (post ~ /^[[:space:]]*(if|for|foreach|catch)/ ? post ~ /\)[[:space:]]*$/ && delta(post, "(", ")") == 0 : delta(post, "(", ")") > 0) COND_NEXT = k
}

function cond_indent(m,    s, ind, k, e) {
  s = m; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
  if (FNR == block_line || s == "") return
  if (bracket_depth > 0) { ca_class(m, ""); return }
  ind = indent_of(raw)
  while (CR_N > 0 && CR_L[CR_N] >= ind) cr_pop()
  k = ""
  if (s ~ /^(if|elif)[[:space:]]/ || s ~ /^except([[:space:]]|:)/) k = "b"
  else if (match(s, /^(async[[:space:]]+)?for[[:space:]].*[[:space:]]in[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*:/)) {
    e = substr(s, RSTART, RLENGTH); sub(/[[:space:]]*:$/, "", e); sub(/.*[[:space:]]/, "", e); sub(/\..*/, "", e)
    k = loop_kind(e)
  }
  ca_class(m, k)
  if (k != "" && s ~ /:$/) cr_push(k, ind)
}

function cond_scan(m) {
  if (LEXER == "python") cond_indent(m)
  else if (LEXER != "bash") cond_brace(m)
}

# ---------------------------------------------------------------------------
# rule-recomputed-derived: the expected side of an equality is built from the
# arguments of the call on the other side with an operator or an aggregate
# (items.reduce(...), sum(xs), a + b), directly or through the one in-test
# binding of a name. Its free identifiers (lambda parameters and member names
# dropped) must all be arguments of that call. A file holding a property-test
# marker is never judged, and an adapter turns the rule off with rules_off.
# ---------------------------------------------------------------------------

# The free identifiers of s, space-separated: no member names, no lambda
# parameters, no keywords or aggregate names, nothing inside a string. For
# PowerShell, its $variables.
function idents(s,    params, out, t, name, prev) {
  gsub(/'[^']*'|"[^"]*"|`[^`]*`/, "\"\"", s)
  out = ""
  if (LEXER == "pwsh") {
    while (match(s, /\$[A-Za-z_][A-Za-z0-9_]*/)) {
      name = tolower(substr(s, RSTART + 1, RLENGTH - 1))
      s = substr(s, RSTART + RLENGTH)
      if (name !~ /^(_|true|false|null|psitem)$/) out = out " " name
    }
    return out
  }
  params = ""
  t = s
  while (match(t, /(\([^()]*\)|[A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*=>/)) { params = params " " substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH) }
  t = s
  while (match(t, /lambda[^:]*:/)) { params = params " " substr(t, RSTART + 6, RLENGTH - 7); t = substr(t, RSTART + RLENGTH) }
  gsub(/[^A-Za-z0-9_$]+/, " ", params)
  params = " " params " "
  t = s
  while (match(t, /[A-Za-z_$][A-Za-z0-9_$]*/)) {
    name = substr(t, RSTART, RLENGTH)
    prev = RSTART > 1 ? substr(t, RSTART - 1, 1) : ""
    t = substr(t, RSTART + RLENGTH)
    if (prev ~ /[.0-9]/ || index(params, " " name " ")) continue
    if (name ~ /^(new|await|typeof|true|false|null|undefined|this|function|return|async|lambda|for|in|if|else|and|or|not|None|True|False|var|nil|reduce|sum|Sum|map|len|Math)$/) continue
    out = out " " name
  }
  return out
}

# x is the call under test, y the expected side.
function derived_side(x, y,    name, args, key, short, e, ids, n, id, i, ar) {
  x = trim(x); y = trim(y)
  sub(/^await[[:space:]]+/, "", x)
  if (LEXER == "pwsh") {
    x = unparen(x)
    if (!match(x, /^[A-Za-z][A-Za-z0-9]*-[A-Za-z0-9]+([[:space:]]|$)/)) return 0
    name = trim(substr(x, 1, RLENGTH)); args = substr(x, RLENGTH + 1)
  } else {
    if (!match(x, /^[A-Za-z_$][A-Za-z0-9_$.]*[[:space:]]*(<[^<>()]*>)?[[:space:]]*\(/)) return 0
    name = substr(x, 1, RLENGTH)
    if (!extract_parens(x, RLENGTH)) return 0
    args = EXTRACT
    sub(/[[:space:]]*(<[^<>()]*>)?[[:space:]]*\($/, "", name)
  }
  if (y ~ (LEXER == "pwsh" ? "^\\$[A-Za-z_][A-Za-z0-9_]*$" : "^[A-Za-z_$][A-Za-z0-9_$]*$")) {
    key = y; sub(/^\$/, "", key)
    if (LEXER == "pwsh") key = tolower(key)
    if (DV_N[BID, key] != 1) return 0
    y = DV_RHS[BID, key]
  }
  # A spread copies an input whole ({ ...input, id: 1 }, {**payload, "id": 1}),
  # and a length (a.length + b.length, len(items) * 5) states an invariant:
  # neither rebuilds the value the way the code does, so neither is an input.
  e = y
  gsub(/[{,][[:space:]]*(\.\.\.|\*\*)[[:space:]]*[A-Za-z_$][A-Za-z0-9_$.]*/, "{", e)
  if (e !~ /[+*]|(^|[^A-Za-z0-9_$])(reduce|sum|Sum|Aggregate|map)[[:space:]]*\(|[Mm]easure-[Oo]bject[^|]*-[Ss]um/) return 0  # spellchecker:disable-line
  short = LEXER == "pwsh" ? tolower(name) : name
  sub(/^.*\./, "", short)
  if (index(LEXER == "pwsh" ? tolower(y) : y, short (LEXER == "pwsh" ? "" : "("))) return 0
  gsub(/[A-Za-z_$][A-Za-z0-9_$.]*[[:space:]]*\.[[:space:]]*(length|Length|Count|size)([^A-Za-z0-9_$]|$)/, " ", e)
  gsub(/(^|[^A-Za-z0-9_.])len[[:space:]]*\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\)/, " ", e)
  ids = idents(e)
  n = split(ids, id, " ")
  if (n == 0) return 0
  ar = " " idents(args) " "
  for (i = 1; i <= n; i++) if (!index(ar, " " id[i] " ")) return 0
  DV_DETAIL = "expected value " snippet(y) " is recomputed from the arguments of " name
  return 1
}

function derived_check(a, b, tkind) {
  if (!LINE_IN_TEST || PROP_FILE) return 0
  if (derived_side(a, b) || derived_side(b, a)) {
    emit(tkind, "recomputed-derived", FNR, DV_DETAIL)
    return 1
  }
  return 0
}

# ---------------------------------------------------------------------------
# Block evaluation — CF1 and CF3
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Same-file helpers. A function defined in the test file outside any test
# asserts when its text, from its definition to the next definition or test
# start, holds an assertion token, a mock verification, a fail call, or a
# throw, raise or reject, or when it calls such a function the same way a test
# would. A test with no assertion token of its own that calls an asserting
# function by name is not a zero-assertion finding. Bash and PowerShell are not tracked: a
# harness file is one block, and a PowerShell call takes no parentheses.
# ---------------------------------------------------------------------------

# The name a definition line defines, or "".
function def_name(m,    s) {
  s = ""
  if (LEXER == "python") {
    if (match(m, /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) s = substr(m, RSTART, RLENGTH)
  } else if (LEXER == "js") {
    if (match(m, /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]*]+[A-Za-z_$][A-Za-z0-9_$]*/)) s = substr(m, RSTART, RLENGTH)
    else if (match(m, /^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(:[^=]*)?=[[:space:]]*(async[[:space:]]+)?(function|\(|[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=>)/)) {
      s = substr(m, RSTART, RLENGTH); sub(/[[:space:]]*(:[^=]*)?=.*$/, "", s)
    }
  } else if (LEXER == "cs") {
    if (match(m, /^[[:space:]]*((public|private|protected|internal|static|async|override|virtual|sealed|unsafe|extern|new)[[:space:]]+)+[A-Za-z_][^=(;]*[[:space:]][A-Za-z_][A-Za-z0-9_]*[[:space:]]*(<[^<>()]*>)?[[:space:]]*\(/)) {
      s = substr(m, RSTART, RLENGTH); sub(/[[:space:]]*(<[^<>()]*>)?[[:space:]]*\($/, "", s)
    }
  } else if (LEXER == "go") {
    if (match(m, /^func[[:space:]]+(\([^)]*\)[[:space:]]*)?[A-Za-z_][A-Za-z0-9_]*/)) s = substr(m, RSTART, RLENGTH)
  }
  sub(/^.*[^A-Za-z0-9_$]/, "", s)
  return s
}

# A line outside every test: it opens, continues or closes a function. A
# code line indented no deeper than an open definition closes it, unless it
# starts with ) or ], closing a signature split over lines, or with the {
# opening the body on a line of its own. A definition indented deeper than
# the open one nests in it, so a line of the inner function is also a line
# of the outer.
function helper_scan(m,    name, ind, k, calls) {
  if (m ~ /^[[:space:]]*$/) return
  if (has(m, R_START)) { HK = 0; return }
  ind = indent_of(m)
  name = def_name(m)
  while (HK > 0 && HI[HK] >= ind && (name != "" || m !~ /^[[:space:]]*([])]|\{)/)) HK--
  if (name != "") { HK++; HI[HK] = ind; HD[HK] = ++DEF_N; DEF_NAME[DEF_N] = name; DEF_CLS[DEF_N] = CLS_K ? CLS_NAME[CLS_K] : "" }
  if (HK > 0 && (has(m, R_ANY) || has(m, R_MOCKA) || has(m, R_FAILC) || m ~ /(^|[^A-Za-z0-9_$.])((throw|raise)([^A-Za-z0-9_$]|$)|reject[[:space:]]*\()/))
    for (k = 1; k <= HK; k++) DEF_ASSERTS[HD[k]] = 1
  # A definition line is read from after the name it defines.
  if (name != "") m = substr(m, index(m, name) + length(name))
  if (HK > 0 && (calls = called_names(m)) != "")
    for (k = 1; k <= HK; k++) DEF_CALLS[HD[k]] = DEF_CALLS[HD[k]] calls
}

# The class a line sits in, by indentation as helper_scan tracks functions:
# the innermost open class is CLS_NAME[CLS_K].
function cls_scan(m,    ind, re) {
  if (m ~ /^[[:space:]]*$/) return
  ind = indent_of(m)
  while (CLS_K > 0 && CLS_I[CLS_K] >= ind && m !~ /^[[:space:]]*([])]|\{)/) CLS_K--
  if (LEXER == "cs") re = "^[[:space:]]*([a-z]+[[:space:]]+)*(class|record|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*"
  else if (LEXER == "python" || LEXER == "js") re = "^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?)?(abstract[[:space:]]+)?class[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*"
  else return
  if (match(m, re)) { CLS_K++; CLS_I[CLS_K] = ind; CLS_NAME[CLS_K] = substr(m, RSTART, RLENGTH); sub(/^.*[^A-Za-z0-9_$]/, "", CLS_NAME[CLS_K]) }
}

# The names blk calls bare or on self, this or cls, space-separated, a call
# on self, this or cls marked with a leading dot, the test's own name left
# out: os.write( is not a call to the file's write.
function called_names(blk,    out, t, pre) {
  out = ""
  if (SHELL_LEX) return out
  while (match(blk, /[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(<[^<>()]*>)?[[:space:]]*\(/)) {
    t = substr(blk, RSTART, RLENGTH)
    pre = substr(blk, 1, RSTART - 1)
    blk = substr(blk, RSTART + RLENGTH)
    sub(/[[:space:]]*(<[^<>()]*>)?[[:space:]]*\($/, "", t)
    if (t == block_name) continue
    if (pre ~ /\.[[:space:]]*$/) {
      if (pre !~ /(^|[^A-Za-z0-9_$.])(self|this|cls)[[:space:]]*\.[[:space:]]*$/) continue
      t = "." t
    }
    out = out " " t
  }
  return out
}

# Whether a test in class cls that makes these calls reaches an asserting
# helper. A call on self or this, and a bare C# call, names the method of the
# test's own class, a bare Python or JS call a module function; when that
# scope defines the name, every definition of it there (C# overloads) must
# assert. A name the scope does not define, as a base class's method, counts
# when any definition of it in the file asserts.
function calls_helper(calls, cls,    n, c, i, name, key) {
  n = split(calls, c, " ")
  for (i = 1; i <= n; i++) {
    name = c[i]; sub(/^\./, "", name)
    key = (c[i] ~ /^\./ || LEXER == "cs" ? cls : "") SUBSEP name
    if (key in SCOPE_DEFS) { if (SCOPE_ASSERTS[key] == SCOPE_DEFS[key]) return 1 }
    else if (name in NAME_ASSERTS) return 1
  }
  return 0
}

function helper_mark(i) {
  SCOPE_ASSERTS[DEF_CLS[i] SUBSEP DEF_NAME[i]]++
  NAME_ASSERTS[DEF_NAME[i]] = 1
}

# Whether definition i calls its own name while another definition of that
# name in its scope asserts: an overload delegating to one that asserts.
function delegates_to_overload(i,    key) {
  key = DEF_CLS[i] SUBSEP DEF_NAME[i]
  return SCOPE_ASSERTS[key] > 0 && (index(DEF_CALLS[i] " ", " " DEF_NAME[i] " ") || index(DEF_CALLS[i] " ", " ." DEF_NAME[i] " "))
}

# A helper that calls an asserting helper asserts too, to any depth: repeat
# until no definition changes.
function helper_verdicts(    i, changed) {
  for (i = 1; i <= DEF_N; i++) SCOPE_DEFS[DEF_CLS[i] SUBSEP DEF_NAME[i]]++
  for (i = 1; i <= DEF_N; i++) if (i in DEF_ASSERTS) helper_mark(i)
  do {
    changed = 0
    for (i = 1; i <= DEF_N; i++)
      if (!(i in DEF_ASSERTS) && (calls_helper(DEF_CALLS[i], DEF_CLS[i]) || delegates_to_overload(i))) { DEF_ASSERTS[i] = 1; helper_mark(i); changed = 1 }
  } while (changed)
}

function eval_block(    blk, stripped, mocka_n, kind, calls) {
  blk = block_masked
  # A test that skips itself from inside its body does not run: not judged.
  if (has(blk, R_BODY_SKIP)) return
  blocks++
  if (SRC_PEND != "") src_flush()
  g8_eval()
  if (block_raw) return
  kind = block_exempt ? "X" : "F"
  if (!has(blk, R_ANY) && !has(blk, R_MOCKA) && !BANG_LAST) {
    # A call to a same-file function may be the assertion; the verdict waits
    # for END, when every function in the file has been read.
    if ((calls = called_names(blk)) == "") emit(kind, "zero-assertion", block_line, "test '" block_name "' has 0 assertion tokens")
    else if (!INVENTORY && !index(RULES_OFF, "|zero-assertion|") && (SCOPE == "" || in_scope(block_line, block_hi))) {
      ZA_N++; ZA_CALLS[ZA_N] = calls; ZA_CLS[ZA_N] = block_cls
      ZA_REC[ZA_N] = sprintf("%s\tzero-assertion\t%d\t%s\n", kind, block_line, clean_detail("test '" block_name "' has 0 assertion tokens"))
    }
    return
  }
  if (OR_W && !OR_S && !OR_P)
    emit(kind, "weak-oracle", OR_WLINE, "test '" block_name "': the only oracle passes for almost any value: " OR_WSNIP)
  if (OR_P && !OR_S && !OR_W)
    emit(kind, "snapshot-only", OR_PLINE, "test '" block_name "': snapshot is the only oracle: review it as code")
  # An else gives the other path its own assertions; a length check makes an
  # empty result fail. Either way some assertion runs.
  if (CA_IN && !CA_OUT && blk !~ /(^|[^A-Za-z0-9_$])else([^A-Za-z0-9_$]|$)/ && !has(blk, R_COUNT))
    emit(kind, "conditional-assertion", CA_LINE, "test '" block_name "': every assertion sits inside an if, a catch or a loop over a result, so a path runs none: " CA_SNIP)
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
  block_cls = CLS_K ? CLS_NAME[CLS_K] : ""
  block_masked = ""
  block_exempt = (raw ~ R_EXEMPT || prev_raw ~ R_EXEMPT)
  block_raw = 0; BW1 = BW2 = ""
  prev_code = G8_CAND = G8_BOUND = ""
  RUN_PEND = BANG_PEND = GO_IF = 0
  BID++
  OR_S = OR_W = OR_P = OR_WLINE = OR_PLINE = 0
  CD = CR_N = CR_LOOPS = CR_BR = CA_IN = CA_OUT = CA_LINE = 0
  COND_NEXT = SRC_PEND = SIG = PM_NAME = ""
  SIG_OPEN = LEXER == "python"
  SH_ACT = SH_FN = PS_PEND = 0
}

# block_raw: an idiom or a delegation matched the raw text of this line and
# the two before it, which counts as an assertion. The per-line rules that
# need to know they are inside a test run from here.
function append_block(m, r) {
  block_masked = block_masked m "\n"
  block_last = FNR
  LINE_IN_TEST = 1
  # The def's signature, up to the parenthesis that closes its parameters.
  if (SIG_OPEN) { SIG = SIG " " m; if (index(SIG, "(") && delta(SIG, "(", ")") <= 0) SIG_OPEN = 0 }
  if (r ~ R_EXEMPT) block_exempt = 1
  if (R_RAW != "" && !block_raw) {
    if ((BW2 " " BW1 " " r) ~ R_RAW) block_raw = 1
    BW2 = BW1; BW1 = r
  }
  # The start line names the test; in cs, python and go that name is code, and
  # a test named check_x would read as an assertion.
  OR_S0 = OR_S
  if (FNR != block_line || LEXER == "js" || LEXER == "pwsh") oracle_line(m, r)
  if (LEXER != "bash") { cond_scan(m); bind_scan(m, r) }
  else sh_act_scan(m)
  if (FNR != block_line) inert_scan(m, r)
  src_scan(m, r)
  if (LEXER == "js" || LEXER == "python") g8_bind(m, r)
  if (m !~ /^[[:space:]]*$/) prev_code = code_tail(m, r)
}

function close_block() {
  in_test = 0
  # A brace block ends on its closing line; an indent block closes on the
  # next dedented line, so its extent ends at the last line it took.
  block_hi = MODEL == "indent" ? block_last : FNR
  closed_lo = block_line; closed_at = FNR
  if (PEND != "" && in_scope(block_line, block_hi)) printf "%s", PEND
  PEND = ""
  closing = 1; inert_close(); eval_block(); closing = 0
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
# line (js) that closes once its braces and the call's parentheses both have, so
# a call split before its body brace keeps its body. brace_decl: test_start
# attributes, then a method signature opens a brace or expression body (cs).
# indent: a test_start def opens a block its indentation closes (python).
# ---------------------------------------------------------------------------

function brace_call() {
  if (in_test) {
    append_block(masked, raw)
    depth += brace_delta(masked)
    call_depth += delta(masked, "(", ")")
    if (depth <= 0 && call_depth <= 0) close_block()
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
      call_depth = delta(substr(masked, RSTART), "(", ")")
      if (depth <= 0 && call_depth <= 0) close_block()
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

# test_skip here matches a decorator on a line above the def, or above a class,
# which skips every test indented under it (skip_cls is that class's indent).
# A line inside open brackets continues the one before it, so it never dedents
# and never resets a pending skip: a signature split over lines closes on its
# ") -> None:", not the block, and a decorator split over lines stays one.
function indent(    code) {
  code = masked !~ /^[[:space:]]*$/ && bracket_depth <= 0
  if (skip_cls >= 0 && code && indent_of(raw) <= skip_cls) skip_cls = -1
  if (in_test && code && indent_of(raw) <= def_indent) close_block()
  if (in_test) append_block(masked, raw)
  else if (skip_cls < 0 && bracket_depth <= 0) {
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
    } else if (pending_skip && masked ~ /^[[:space:]]*class[[:space:]]/) {
      skip_cls = indent_of(raw); pending_skip = 0
    } else if (masked !~ /^[[:space:]]*@/ && code) pending_skip = 0
  }
  bracket_depth += delta(masked, "([{", ")]}")
  taut_scan(raw, masked)
}

# test_skip here matches any attribute in the stack, before or after the test
# attribute. An attribute is a line opening with "["; a signature is a line
# with a C# modifier or return type before its "(".
function brace_decl() {
  # A skip in the attribute stack of a class skips every test in it: consume
  # the class's braces, open nothing and judge nothing.
  if (pending_skip && masked ~ /(^|[^A-Za-z0-9_])class[[:space:]]/) {
    sr = 1; sr_open = sr_depth = pending_attr = pending_skip = 0
  }
  if (sr) {
    sr_depth += brace_delta(masked)
    if (index(masked, "{")) sr_open = 1
    if (sr_open && sr_depth <= 0) sr = 0
  } else if (in_test) {
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
  if (INVENTORY) inv_line()
  LINE_IN_TEST = 0
  if (SHELL_LEX) sh_assign(masked)
  if (LEXER == "bash") sh_file_facts()

  if (!SHELL_LEX) cls_scan(masked)
  if (MODEL == "file") whole_file()
  else if (MODEL == "indent") indent()
  else if (LEXER == "cs") brace_decl()
  else brace_call()
  if (!LINE_IN_TEST && !SHELL_LEX) helper_scan(masked)
  prev_raw = raw
}

END {
  if (FATAL) exit 2
  # A fragment can also end inside a JS template, a block comment, a Python
  # triple-quoted string or a C# verbatim string; the rules never ask.
  if (INVENTORY && (mask_open() || S_bc || S_tpl || S_triple || S_verb)) print INVENTORY "\tunjudged"
  else if (mask_open()) print "L\t1"
  else if (in_test) close_block()
  helper_verdicts()
  for (i = 1; i <= ZA_N; i++) if (!calls_helper(ZA_CALLS[i], ZA_CLS[i])) printf "%s", ZA_REC[i]
  if (!INVENTORY) printf "B\t%d\n", blocks
}
