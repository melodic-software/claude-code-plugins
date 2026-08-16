# cant-fail-scan.awk — per-file rule engine for cant-fail-scan.sh. Not a
# standalone entry point: the driver resolves the scan root, walks the tree,
# and aggregates; this program judges ONE test file per invocation.
#
# Invocation: awk -v LANG_ID=<js|py|cs> -f cant-fail-scan.awk <file>
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

  # Two-argument equality helpers for the recomputed-expectation rule; one
  # combined case-sensitive list, matched by substring lookup, so a language
  # gains nothing from a private copy. Inequality asserts are deliberately
  # absent: Assert.NotEqual(f(2), f(2)) is a always-fail defect, not this rule.
  TAUT_FUNCS = "assert.equal|assert.strictEqual|assert.deepEqual|assert.deepStrictEqual|assertEqual|assertEquals|assertAlmostEqual|Assert.Equal|Assert.StrictEqual|Assert.Same|Assert.AreEqual|Assert.AreSame"

  if (LANG_ID == "js") {
    # The trailing t.<method> alternative is the AVA / node-tap vocabulary —
    # those runners assert through the test-context object, not expect/assert.
    ANY_ERE = "expect[[:space:]]*\\(|[Aa]ssert|[Ss]hould|[Vv]erify|[Tt]hrows|rejects|resolves|[Ss]napshot|[Cc]heck|[Ee]nsure|[Vv]alidate|fail[[:space:]]*\\(|(^|[^A-Za-z0-9_$.])t[[:space:]]*\\.[[:space:]]*(is|not|deepEqual|notDeepEqual|like|equal|notEqual|same|notSame|strictSame|has|ok|notOk|truthy|falsy|true|false|pass|fail|throws|throwsAsync|notThrows|notThrowsAsync|regex|notRegex|match|snapshot|plan|end|type|emits)([^A-Za-z0-9_]|$)"  # spellchecker:disable-line
    MOCKA_ERE = "toHaveBeenCalled|toBeCalled|toHaveReturned|toHaveBeenNth|toHaveBeenLast|sinon\\.assert|calledOnce|calledTwice|calledThrice|calledWith|callCount"
    MOCKC_ERE = "jest\\.(mock|fn|spyOn)|vi\\.(mock|fn|spyOn)|sinon\\.(stub|spy|fake|mock)|createMock|\\.mockReturnValue|\\.mockResolvedValue|\\.mockImplementation"
    # Full mock-interaction chains, removed before deciding whether a real
    # value assertion remains. [^()]*(\([^()]*\)[^()]*)* allows one nesting
    # level; a deeper chain survives the strip and reads as a value assertion
    # — the conservative direction.
    STRIP_ERE = "expect[[:space:]]*\\([^()]*(\\([^()]*\\)[^()]*)*\\)[[:space:]]*(\\.[[:space:]]*not)?[[:space:]]*\\.[[:space:]]*(toHaveBeenCalled|toBeCalled|toHaveReturned|toHaveBeenNth|toHaveBeenLast)[A-Za-z]*[[:space:]]*\\([^()]*(\\([^()]*\\)[^()]*)*\\)|sinon\\.assert\\.[A-Za-z]+[[:space:]]*\\([^()]*(\\([^()]*\\)[^()]*)*\\)"
    TEST_START_ERE = "(^|[^A-Za-z0-9_$.])(it|test)[[:space:]]*(\\.[[:space:]]*(only|concurrent|failing|sequential))*[[:space:]]*(\\.[[:space:]]*each[[:space:]]*\\([^)]*\\)[[:space:]]*)?\\("
    TEST_SKIP_ERE = "(^|[^A-Za-z0-9_$.])(xit|xtest)[[:space:]]*\\(|(^|[^A-Za-z0-9_$.])(it|test)[[:space:]]*\\.[[:space:]]*(skip|todo)"
    SUITE_SKIP_ERE = "(^|[^A-Za-z0-9_$.])(xdescribe|(describe|context|suite)[[:space:]]*\\.[[:space:]]*skip)[[:space:]]*\\("  # spellchecker:disable-line
  } else if (LANG_ID == "py") {
    ANY_ERE = "[Aa]ssert|\\.raises|\\.warns|self\\.fail|[Ee]xpect|[Vv]erify|[Ss]hould|[Cc]heck|[Ee]nsure|[Vv]alidate"  # spellchecker:disable-line
    MOCKA_ERE = "assert_called|assert_any_call|assert_has_calls|assert_not_called|assert_awaited|call_count|mock_calls|\\.called([^A-Za-z0-9_]|$)"
    MOCKC_ERE = "MagicMock|AsyncMock|Mock\\(|create_autospec|patch\\(|patch\\.object|mocker\\."
    # Second alternative: an assert statement WHOSE SUBJECT is a mock property.
    # The property tokens carry word-boundary guards so a real attribute that
    # merely contains one (result.called_back) is never stripped.
    STRIP_ERE = "\\.assert_(called|any_call|has_calls|not_called|awaited)[a-z_]*[[:space:]]*\\([^()]*(\\([^()]*\\)[^()]*)*\\)|assert[[:space:]][^\\n]*([^A-Za-z0-9_](call_count|mock_calls)([^A-Za-z0-9_]|$)|\\.called([^A-Za-z0-9_]|$))[^\\n]*"
    TEST_START_ERE = "^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\\("
    SKIP_DECOR_ERE = "^[[:space:]]*@[[:space:]]*(pytest[[:space:]]*\\.[[:space:]]*mark[[:space:]]*\\.[[:space:]]*)?skip(if)?([^A-Za-z0-9_]|$)|^[[:space:]]*@[[:space:]]*unittest[[:space:]]*\\.[[:space:]]*skip"
  } else if (LANG_ID == "cs") {
    ANY_ERE = "[Aa]ssert|\\.Should|Should\\.|[Ee]xpect|Verify|Received|MustHaveHappened|MustNotHaveHappened|Throws|[Ss]napshot|[Cc]heck|[Ee]nsure|[Vv]alidate"
    MOCKA_ERE = "\\.Verify[[:space:]]*\\(|\\.VerifyAll|\\.VerifyNoOtherCalls|\\.Received|\\.DidNotReceive|MustHaveHappened|MustNotHaveHappened"
    MOCKC_ERE = "new[[:space:]]+Mock<|Mock\\.Of<|Substitute\\.For<|A\\.Fake<"
    # Each mock-interaction chain is stripped as a BOUNDED expression — the
    # Received/DidNotReceive forms include one chained call — never to end of
    # line, so a same-line real assertion after the chain survives the strip.
    STRIP_ERE = "\\.[[:space:]]*Verify(All|NoOtherCalls)?(<[^<>]*>)?[[:space:]]*\\([^()]*(\\([^()]*\\)[^()]*)*\\)|\\.[[:space:]]*Received[[:space:]]*(\\([^()]*\\))?(\\.[A-Za-z_]+[[:space:]]*\\([^()]*(\\([^()]*\\)[^()]*)*\\))?|\\.[[:space:]]*DidNotReceive[[:space:]]*(\\(\\))?(\\.[A-Za-z_]+[[:space:]]*\\([^()]*(\\([^()]*\\)[^()]*)*\\))?|MustHaveHappened[A-Za-z]*[[:space:]]*(\\([^()]*\\))?|MustNotHaveHappened[A-Za-z]*[[:space:]]*(\\([^()]*\\))?"
    ATTR_ERE = "^[[:space:]]*\\[[[:space:]]*(Fact|Theory|Test([^A-Za-z0-9_]|$)|TestMethod|TestCase|DataTestMethod)"
    ATTR_ANY_ERE = "^[[:space:]]*\\["
    ATTR_SKIP_ERE = "Skip[[:space:]]*=|Ignore"
    SIG_ERE = "(public|private|protected|internal|async|static|void|Task)[^=]*\\("
  } else {
    printf "E\tunknown LANG_ID '%s'\n", LANG_ID
    FATAL = 1
    exit 2
  }
  EXEMPT_ERE = "cant-fail-ok:"
}

# ---------------------------------------------------------------------------
# Masking. One function per language; string/comment interiors become spaces,
# LENGTH-PRESERVING, so token matches and brace counts run over code only and
# raw/masked column positions stay aligned. Multi-line states (block comments,
# template literals, triple quotes, verbatim strings) are file-scoped globals.
# ---------------------------------------------------------------------------

function mask_js(s,    out, i, c, c2, n, inclass) {
  out = ""; n = length(s); i = 1
  last_sig = ""  # per line: a regex literal cannot span lines, nor can the operator before it
  while (i <= n) {
    c = substr(s, i, 1); c2 = substr(s, i, 2)
    if (S_bc) { if (c2 == "*/") { S_bc = 0; out = out "  "; i += 2 } else { out = out " "; i++ }; continue }
    if (S_tpl) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == "`") { S_tpl = 0; out = out " "; i++; last_sig = "`"; continue }
      out = out " "; i++; continue
    }
    if (S_str) {
      if (c == "\\") { out = out "  "; i += 2; continue }
      if (c == S_q) { S_str = 0; last_sig = c }
      out = out " "; i++; continue
    }
    if (c2 == "//") { while (i <= n) { out = out " "; i++ }; continue }
    if (c2 == "/*") { S_bc = 1; out = out "  "; i += 2; continue }
    if (c == "'" || c == "\"") { S_str = 1; S_q = c; out = out " "; i++; continue }
    if (c == "`") { S_tpl = 1; out = out " "; i++; continue }
    if (c == "/") {
      # Regex literal, decided by what precedes it: after an operator or opening
      # delimiter a '/' cannot be division. Mask through the closing '/', where
      # '/' inside a [...] class is literal and '\' escapes; flags follow. An
      # unterminated candidate masks to end of line — a string-ish context
      # either way. Wrongly reading division as a regex would mask real code,
      # so the trigger set stays narrow (no '>', no keyword heuristics).
      if (last_sig == "" || index("(,=:[!&?;{|", last_sig) > 0) {
        out = out " "; i++
        inclass = 0
        while (i <= n) {
          c = substr(s, i, 1)
          if (c == "\\") { out = out "  "; i += 2; continue }
          if (c == "[") inclass = 1
          else if (c == "]") inclass = 0
          else if (c == "/" && !inclass) {
            out = out " "; i++
            while (i <= n && substr(s, i, 1) ~ /[a-z]/) { out = out " "; i++ }
            break
          }
          out = out " "; i++
        }
        last_sig = "/"
        continue
      }
    }
    out = out c; i++
    if (c != " " && c != "\t") last_sig = c
  }
  S_str = 0  # ' and " never span lines
  return out
}

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

function emit(kind, slug, line, detail) {
  printf "%s\t%s\t%d\t%s\n", kind, slug, line, clean_detail(detail)
}

# ---------------------------------------------------------------------------
# CF2 — recomputed expectation (self-identical actual/expected), line-scoped.
# The masked line gates (no findings from comments or strings); the raw line
# is what the expressions are read from.
# ---------------------------------------------------------------------------

function taut_scan(raw_line, masked_line,    tkind, a, b, rest, m, names, i, p, fn, expr) {
  tkind = (raw_line ~ EXEMPT_ERE || prev_raw ~ EXEMPT_ERE) ? "X" : "F"
  # expect(A).toBe(A) family. The masked match position indexes into the RAW
  # line — masking is length-preserving, so the columns align, and an earlier
  # "expect" inside a string cannot shadow the real call site.
  if (LANG_ID == "js" && match(masked_line, /expect[[:space:]]*\(/) > 0) {
    p = RSTART
    if (p > 0) {
      m = p + 6
      while (substr(raw_line, m, 1) ~ /[[:space:]]/) m++
      if (extract_parens(raw_line, m)) {
        a = EXTRACT
        rest = substr(raw_line, EXTEND + 1)
        if (match(rest, /^[[:space:]]*\.[[:space:]]*(toBe|toEqual|toStrictEqual)[[:space:]]*\(/) > 0) {
          p = index(rest, "(")
          if (p > 0 && extract_parens(rest, p)) {
            b = EXTRACT
            expr = norm(a)
            if (expr != "" && expr == norm(b)) {
              emit(tkind, "recomputed-expectation", FNR, "expect(" expr ") compared to itself")
              return
            }
          }
        }
      }
    }
  }
  # two-argument equality helpers, all languages
  split(TAUT_FUNCS, names, "|")
  for (i in names) {
    fn = names[i]
    if (fn == "") continue
    if (index(masked_line, fn) == 0) continue
    p = index(raw_line, fn)
    if (p == 0) continue
    m = p + length(fn)
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
  # python assert EXPR == EXPR
  if (LANG_ID == "py" && masked_line ~ /^[[:space:]]*assert[[:space:]]/) {
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
  blocks++
  blk = block_masked
  kind = block_exempt ? "X" : "F"
  if (blk !~ ANY_ERE && blk !~ MOCKA_ERE) {
    emit(kind, "zero-assertion", block_line, "test '" block_name "' has 0 assertion tokens")
    return
  }
  if ((blk ~ MOCKC_ERE || file_mock) && blk ~ MOCKA_ERE) {
    stripped = blk
    gsub(STRIP_ERE, "", stripped)
    if (stripped !~ ANY_ERE) {
      mocka_n = count_matches(blk, MOCKA_ERE)
      emit(kind, "mock-only-oracle", block_line, "test '" block_name "': " mocka_n " mock-interaction assertion(s), no assertion on a real collaborator detected")
    }
  }
}

function open_block(line, name) {
  in_test = 1
  block_line = line
  block_name = name
  block_masked = ""
  block_exempt = (raw ~ EXEMPT_ERE || prev_raw ~ EXEMPT_ERE)
}

function append_block(m, r) {
  block_masked = block_masked m "\n"
  if (r ~ EXEMPT_ERE) block_exempt = 1
}

function close_block() { in_test = 0; eval_block() }

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
# Main loop
# ---------------------------------------------------------------------------

{
  raw = $0
  sub(/\r$/, "", raw)
  if (LANG_ID == "js") masked = mask_js(raw)
  else if (LANG_ID == "py") masked = mask_py(raw)
  else masked = mask_cs(raw)

  if (masked ~ MOCKC_ERE) file_mock = 1

  if (LANG_ID == "js") {
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
    } else if (masked ~ SUITE_SKIP_ERE) {
      match(masked, SUITE_SKIP_ERE)
      sr = 1
      sr_depth = brace_delta(substr(masked, RSTART))
      if (sr_depth <= 0) sr = 0
    } else {
      if (masked ~ TEST_START_ERE && masked !~ TEST_SKIP_ERE) {
        match(masked, TEST_START_ERE)
        open_block(FNR, first_quoted(substr(raw, RSTART)))
        append_block(masked, raw)
        depth = brace_delta(substr(masked, RSTART))
        if (depth <= 0) close_block()
      }
      taut_scan(raw, masked)
    }
  } else if (LANG_ID == "py") {
    if (in_test && masked !~ /^[[:space:]]*$/ && indent_of(raw) <= def_indent) close_block()
    if (!in_test) {
      if (masked ~ SKIP_DECOR_ERE) pending_skip = 1
      if (masked ~ TEST_START_ERE) {
        if (pending_skip) pending_skip = 0
        else {
          match(masked, /def[[:space:]]+test[A-Za-z0-9_]*/)
          open_block(FNR, substr(masked, RSTART + 4, RLENGTH - 4))
          sub(/^[[:space:]]+/, "", block_name)
          def_indent = indent_of(raw)
          append_block(masked, raw)
        }
      } else if (masked !~ /^[[:space:]]*@/ && masked !~ /^[[:space:]]*$/) pending_skip = 0
    } else append_block(masked, raw)
    taut_scan(raw, masked)
  } else {
    # cs
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
        if (index(masked, "{") > 0) {
          body_open = 1
          depth = brace_delta(masked)
          if (depth <= 0) close_block()
        } else if (index(masked, "=>") > 0) {
          expr_body = 1
          if (masked ~ /;[[:space:]]*$/) { expr_body = 0; close_block() }
        }
      }
    } else if (pending_attr && masked ~ SIG_ERE && masked !~ ATTR_ANY_ERE) {
      pending_attr = 0
      if (pending_skip) pending_skip = 0
      else {
        open_block(FNR, cs_method_name(masked))
        append_block(masked, raw)
        body_open = 0; expr_body = 0; depth = 0
        if (index(masked, "{") > 0) {
          body_open = 1
          depth = brace_delta(masked)
          if (depth <= 0) close_block()
        } else if (index(masked, "=>") > 0) {
          expr_body = 1
          if (masked ~ /;[[:space:]]*$/) { expr_body = 0; close_block() }
        }
      }
    } else {
      if (masked ~ ATTR_ERE) {
        pending_attr = 1
        if (masked ~ ATTR_SKIP_ERE) pending_skip = 1
      } else if (masked ~ ATTR_ANY_ERE) {
        # any other attribute in the same stack — a skip marker counts whether
        # it precedes or follows the test attribute
        if (masked ~ ATTR_SKIP_ERE) pending_skip = 1
      } else if (masked !~ /^[[:space:]]*$/) { pending_attr = 0; pending_skip = 0 }
    }
    taut_scan(raw, masked)
  }
  prev_raw = raw
}

END {
  if (FATAL) exit 2
  if (in_test) close_block()
  printf "B\t%d\n", blocks
}
