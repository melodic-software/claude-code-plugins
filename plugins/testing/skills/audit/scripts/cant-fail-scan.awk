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
  last_sig = ""
  NS = split(SCOPE, scope_parts, ",")
  for (i = 1; i <= NS; i++) {
    S_LO[i] = S_HI[i] = scope_parts[i] + 0
    if (scope_parts[i] ~ /-/) S_HI[i] = substr(scope_parts[i], index(scope_parts[i], "-") + 1) + 0
  }
  load_adapter()
}


function load_adapter(    line, f, key, n, i, w, nw, wi) {
  while ((getline line < ADAPTER_TABLE) > 0) {
    split(line, f, "\t")
    if (f[1] != ADAPTER) continue
    key = f[2]
    if (key == "language") LEXER = f[3]
    else if (key == "suppress_marker") R_EXEMPT = f[3]
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
  R_ANY = alt(V["assertion.calls"], V["snapshot"])
  R_RAW = alt(V["assertion.idioms"], V["delegation"])
  R_BODY_SKIP = V["body_skip"]
  N_PIPE = split(V["equality.pipeline"], PIPE, "|")
  for (i = 1; i <= N_PIPE; i++) {
    PIPE_RE[i] = PIPE[i]
    gsub(/[.]/, "\\.", PIPE_RE[i])
    gsub(/ /, "[[:space:]]+", PIPE_RE[i])
  }
  R_MOCKA = V["mock.verify"]
  R_MOCKC = V["mock.create"]
  R_STRIP = V["mock.strip"]
  R_START = V["test_start"]
  R_SKIP = V["test_skip"]
  R_SUITE_SKIP = V["suite_skip"]
  if (R_EXEMPT == "") R_EXEMPT = "cant-fail-ok:"
  R_ASYNC = V["assertion.async"] == "" ? "" : "^(" V["assertion.async"] ")"
  R_INERT = V["assertion.inert"] == "" ? "" : "^(" V["assertion.inert"] ")"
  R_WEAK = V["assertion.weak"]
  R_EXISTS = V["assertion.exists"]
  R_SNAP = V["snapshot"]
  R_COUNT = V["assertion.count"]
  R_FAILC = V["assertion.fail"]
  RULES_OFF = "|" V["rules_off"] "|"
  R_PROP = V["property_markers"]
  CS_VERIFY = 0
  if (LEXER == "cs" && ARGV[1] != "") {
    while ((getline line < ARGV[1]) > 0) {
      if (line ~ /using[[:space:]]+(static[[:space:]]+)?Verify(Xunit|NUnit|MSTest|Tests)([^A-Za-z0-9_]|$)|\[[[:space:]]*UsesVerify/) CS_VERIFY = 1
      if (line !~ /^[[:space:]]*(return|await)[[:space:]]/ && line ~ /^[[:space:]]*([A-Za-z]+[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.?]*[[:space:]]+Verify(Json|Xml|File)?[[:space:]]*(<[^<>]*>)?[[:space:]]*\(/) { CS_VERIFY = 0; break }
    }
    close(ARGV[1])
  }
  if (LEXER == "cs" && ARGV[1] != "") {
    while ((getline line < ARGV[1]) > 0)
      if (line ~ /^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*)?Microsoft\.CodeAnalysis(\.[A-Za-z]+)*\.Testing([^A-Za-z0-9_]|$)/) {
        R_ANY = R_ANY "|\\}[[:space:]]*\\.[[:space:]]*RunAsync[[:space:]]*\\("
        break
      }
    close(ARGV[1])
  }

  R_CALL2 = V["equality.call2"]
  N_CALL2 = split(R_CALL2, CALL2, "|")

  NRW = 0
  n = split(V["equality.receiver"], w, "|")
  for (i = 1; i <= n; i++) {
    nw = index(w[i], ".")
    for (wi = 1; wi <= NRW && RW_NAME[wi] != substr(w[i], 1, nw - 1); wi++) ;
    if (wi > NRW) {
      NRW = wi; RW_NAME[wi] = RW_RE[wi] = substr(w[i], 1, nw - 1); RW_MATCH[wi] = ""
      gsub(/\./, "\\.", RW_RE[wi])
    }
    RW_MATCH[wi] = RW_MATCH[wi] (RW_MATCH[wi] != "" ? "|" : "") substr(w[i], nw + 1)
  }
}

function alt(a, b) { return a == "" ? b : b == "" ? a : a "|" b }

function has(s, re) { return re != "" && s ~ re }


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
    if (c == "#") { out = out blanks(n - i + 1); break }
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
    if (c2 == "//") { out = out blanks(n - i + 1); break }
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

function word_start(s, i) { return i == 1 || substr(s, i - 1, 1) ~ /[[:space:];|&({]/ }

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
      if (S_q == "\"" && substr(s, i, 2) == "$(") { S_str = 0; S_sub[++S_nsub] = 0; out = out "$("; i += 2; continue }
      if (c == (S_q == "\"" ? "\"" : "'")) S_str = 0
      out = out " "; i++; continue
    }
    if (S_nsub > 0 && c == "(") S_sub[S_nsub]++
    if (S_nsub > 0 && c == ")" && S_sub[S_nsub]-- == 0) { S_nsub--; S_str = 1; S_q = "\""; out = out ")"; i++; continue }
    if (c == "\\") { out = out substr(s, i, 2); i += 2; continue }
    if (c == "#" && word_start(s, i) && substr(s, i - 1, 1) != "{") { out = out blanks(n - i + 1); break }
    if (c == "$" && substr(s, i + 1, 1) == "'") { S_str = 1; S_q = "e"; out = out "  "; i += 2; continue }
    if (c == "'" || c == "\"") { S_str = 1; S_q = c; out = out " "; i++; continue }
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

function mask_open() {
  if (LEXER == "bash") return S_str || S_hd || S_nsub > 0
  if (LEXER == "pwsh") return S_str || S_bc || S_hs != ""
  if (LEXER == "go") return S_bc || S_raw
  return 0
}


function brace_delta(s) { return delta(s, "{", "}") }

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

function after_last(s, re) {
  while (match(s, re)) s = substr(s, RSTART + 1)
  return s
}

function clean_detail(s) { gsub(/\t/, " ", s); return s }

function count_matches(s, re,    c) {
  c = 0
  while (match(s, re) > 0) {
    c++
    s = substr(s, RSTART + (RLENGTH > 0 ? RLENGTH : 1))
  }
  return c
}

function first_quoted(s,    q, rest, n, i, c) {
  if (match(s, /['"`]/) == 0) return "(unnamed)"
  q = substr(s, RSTART, 1)
  rest = substr(s, RSTART + 1)
  n = length(rest)
  for (i = 1; i <= n; i++) {
    c = substr(rest, i, 1)
    if (LEXER == "pwsh") {
      if (c == "`" && q == "\"") { i++; continue }
      if (c == q && substr(rest, i + 1, 1) == q) { i++; continue }
    } else if (c == "\\" && !(LEXER == "bash" && q == "'") && !(LEXER == "go" && q == "`")) {
      i++
      continue
    }
    if (c == q) return i == 1 ? "(unnamed)" : substr(rest, 1, i - 1)
  }
  return "(unnamed)"
}

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

function shell_words(s, i) {
  while (substr(s, i, 1) ~ /[[:space:]]/) i++
  i = shell_word(s, i); SW1 = SW
  while (substr(s, i, 1) ~ /[[:space:]]/) i++
  shell_word(s, i); SW2 = SW
  return SW1 != "" && SW2 != ""
}

function unparen(s) {
  if (s ~ /^\$?\(.*\)$/) { sub(/^\$?\(/, "", s); sub(/\)$/, "", s) }
  return s
}

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

function inv_count(s, re) { return re == "" ? 0 : count_matches(s, re) }

function inv_line(    t, n) {
  t = clean_detail(trim(raw))
  if ((n = inv_count(masked, R_START)) > 0) printf "%s\ttest\t%d\t%s\n", INVENTORY, n, t
  if ((n = inv_count(masked, R_ANY) + inv_count(masked, R_MOCKA)) > 0) printf "%s\tassertion\t%d\t%s\n", INVENTORY, n, t
  if ((n = inv_count(masked, R_SKIP) + inv_count(masked, R_BODY_SKIP) + inv_count(masked, R_SUITE_SKIP)) > 0) printf "%s\tskip\t%d\t%s\n", INVENTORY, n, t
  inv_cmp()
}

function inv_cmp(    m, l, r) {
  m = masked
  if (LEXER == "go") {
    if (m !~ /^[[:space:]]*if[[:space:]].*\{[[:space:]]*$/ || m ~ /&&|\|\||;/) return
    if (gsub(/[!=]=/, "&", m) != 1 || !match(m, /[!=]=/)) return
    l = substr(raw, 1, RSTART - 1); r = substr(raw, RSTART + RLENGTH)
    sub(/^[[:space:]]*if[[:space:]]+/, "", l); sub(/\{[[:space:]]*$/, "", r)
  } else if (LEXER == "bash") {
    if (m !~ /^[[:space:]]*\[\[?[[:space:]].*[[:space:]]\]\]?[[:space:]]*$/ || m ~ /&&|\|\||;/) return
    if (gsub(/[[:space:]](==?|!=|-eq|-ne)[[:space:]]/, "&", m) != 1 || !match(m, /[[:space:]](==?|!=|-eq|-ne)[[:space:]]/)) return
    l = substr(raw, 1, RSTART - 1); r = substr(raw, RSTART + RLENGTH)
    sub(/^[[:space:]]*\[\[?[[:space:]]+/, "", l); sub(/[[:space:]]+\]\]?[[:space:]]*$/, "", r)
  } else return
  inv_eq(l, r)
}

function inv_eq(a, b) {
  if (!INVENTORY) return
  a = trim(a); b = trim(b)
  if (is_lit(b) && !is_lit(a)) printf "%s\texpect\t%s\t%s\n", INVENTORY, norm(a), norm(b)
  else if (is_lit(a) && !is_lit(b)) printf "%s\texpect\t%s\t%s\n", INVENTORY, norm(b), norm(a)
}


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

function taut_scan(raw_line, masked_line,    tkind, a, b, rest, m, i, p, fn, expr) {
  tkind = line_kind()
  for (i = 1; i <= NRW; i++) {
    if (match(masked_line, RW_RE[i] "[[:space:]]*\\(") == 0) continue
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
  for (i = 1; i <= N_CALL2; i++) {
    fn = CALL2[i]
    if (index(masked_line, fn) == 0) continue
    p = index(raw_line, fn)
    if (p == 0) continue
    m = p + length(fn)
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
    if (split_top_comma(b)) b = SPLIT1
    inv_eq(a, b)
    expr = norm(a)
    if (expr != "" && expr == norm(b)) {
      emit(tkind, "recomputed-expectation", FNR, fn "(" expr ", " expr ")")
      return
    }
    if (const_check(a, b, tkind) || derived_check(a, b, tkind)) return
  }
  for (i = 1; i <= N_PIPE; i++) {
    if (match(masked_line, "\\|[[:space:]]*" PIPE_RE[i] "([[:space:]]|$)") == 0) continue
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
  if (LEXER == "python" && masked_line ~ /^[[:space:]]*assert[[:space:]]/) {
    rest = substr(raw_line, 1, py_code_len(raw_line))
    sub(/^[[:space:]]*assert[[:space:]]+/, "", rest)
    if (split_top_comma(rest)) rest = SPLIT1
    if (split_top_eq(rest)) {
      inv_eq(EQL, EQR)
      expr = norm(EQL)
      if (expr != "" && expr == norm(EQR)) {
        emit(tkind, "recomputed-expectation", FNR, "assert " expr " == " expr)
      } else if (!const_check(EQL, EQR, tkind)) derived_check(EQL, EQR, tkind)
    }
  }
}


function is_lit(s) {
  if (s ~ /^-?[0-9][0-9_]*(\.[0-9]+)?$/ || s ~ /^(true|false|null|undefined|None|True|False)$/) return 1
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
  if (x == "") return 0
  if (!is_lit(y)) {
    if (g8_path(x) && g8_path(y)) G8_CAND = G8_CAND FNR "\t" tkind "\t" x "\t" y "\tpath\n"
    return 0
  }
  if (is_const(x)) {
    if (SHELL_LEX ? SH_ACT : !g8_no_calls()) return 0
    emit(tkind, "constant-restatement", FNR, "constant " x " compared to the literal " y)
    return 1
  }
  if (g8_path(x)) G8_CAND = G8_CAND FNR "\t" tkind "\t" x "\t" y "\tlit\n"
  return 0
}

function g8_path(s) {
  return (LEXER == "js" || LEXER == "python") && s ~ /^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*|\[[^]()]*\])*$/
}

function g8_root(s) {
  sub(/[.[].*$/, "", s)
  return s
}

function g8_bind(m, r,    re) {
  if (LEXER == "js") re = "^[[:space:]]*(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*([{['\"`0-9-]|true|false|null)"
  else re = "^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*([{['\"0-9-]|True|False|None)"
  if (r !~ re) return
  sub(/^[[:space:]]*((const|let|var)[[:space:]]+)?/, "", m)
  match(m, /^[A-Za-z_$][A-Za-z0-9_$]*/)
  G8_BOUND = G8_BOUND " " substr(m, 1, RLENGTH) " "
}

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

function g8_eval(    n, recs, i, f, root, root2) {
  if (G8_CAND == "" || G8_BOUND == "" || !g8_no_calls()) return
  n = split(G8_CAND, recs, "\n")
  for (i = 1; i < n; i++) {
    split(recs[i], f, "\t")
    root = g8_root(f[3])
    if (!index(G8_BOUND, " " root " ")) continue
    if (f[5] == "lit")
      emit(f[2], "constant-restatement", f[1], root " is a literal bound in the test and " f[3] " is compared to the literal " f[4] " with no code under test called")
    else if (index(G8_BOUND, " " (root2 = g8_root(f[4])) " "))
      emit(f[2], "constant-restatement", f[1], (root == root2 ? root " is a literal" : root " and " root2 " are literals") " bound in the test and " f[3] " is compared to " f[4] " with no code under test called")
  }
}

function sh_assign(m,    s, name) {
  s = m
  while (match(s, /(^|[[:space:];&|(])(local|export|readonly|declare|typeset)?[[:space:]]*(-[A-Za-z]+[[:space:]]+)*[A-Za-z_][A-Za-z0-9_]*\+?=/)) {
    name = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART + RLENGTH)
    sub(/\+?=$/, "", name)
    SH_SET[after_last(name, "[^A-Za-z0-9_]")] = 1
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

function sh_act_scan(m,    s, n, seg, i) {
  s = trim(m)
  if (SH_FN) { SH_FN += brace_delta(m); return }
  if (s == "" || FNR == block_line) return
  if (s ~ /^(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_:]*[[:space:]]*\([[:space:]]*\)[[:space:]]*\{?/ || s ~ /^function[[:space:]]/) {
    SH_FN = brace_delta(m)
    return
  }
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

function sh_file_facts(    name, rhs, v) {
  if (masked ~ /(^|[[:space:];&|])set[[:space:]]+(-[A-Za-z]*e[A-Za-z]*|-o[[:space:]]+errexit)([[:space:]]|$)/ ||
      (FNR == 1 && raw ~ /^#!.*[[:space:]]-[A-Za-z]*e/)) SET_E = 1
  if (masked ~ /(^|[[:space:];&|])(source|\.)[[:space:]]/) SOURCED = 1
  if (masked ~ /(^|[[:space:];&|])(cd|pushd)[[:space:]]/) SH_CD = 1
  if (match(raw, /^[[:space:]]*((local|export|readonly|declare)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/)) {
    name = substr(raw, RSTART, RLENGTH - 1)
    rhs = substr(raw, RSTART + RLENGTH)
    name = after_last(name, "[^A-Za-z0-9_]")
    if (rhs ~ /mktemp|TMP|TEMP|[Tt]mp|[Tt]emp/) SH_TMP[name] = 1
    else if (match(rhs, /\$\{?[A-Za-z_][A-Za-z0-9_]*/)) {
      v = substr(rhs, RSTART, RLENGTH)
      gsub(/[${]/, "", v)
      if (v in SH_TMP) SH_TMP[name] = 1
    }
  }
}


function snippet(r) {
  r = trim(r)
  return length(r) > 60 ? substr(r, 1, 57) "..." : r
}

function line_kind() { return (raw ~ R_EXEMPT || prev_raw ~ R_EXEMPT) ? "X" : "F" }

function stmt_start(    p) {
  if (LEXER == "python") return bracket_depth <= 0 && prev_code !~ /\\[[:space:]]*$/
  p = prev_code
  sub(/[[:space:]]+$/, "", p)
  if (p ~ /[-+*\/%=<>!&|?:,(\[.\\`]$/) return 0
  return p !~ /(^|[^A-Za-z0-9_$])(await|return|yield|void)$/
}

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

function sh_inert(s, r) {
  if (MODEL == "file") {
    if (s == "" || s ~ /^(fi|done|esac|else|elif|then|do|\}|\)|;;)/) { if (s != "") BRK_PEND = ""; return }
    if (BRK_PEND != "" && r !~ /\$\?/ && s !~ /^exit[[:space:]]*;?$/) BRK_OUT = BRK_OUT BRK_PEND
    BRK_PEND = ""
    if (s ~ /^\[\[?[[:space:]][^;&|]*[[:space:]]\]\]?[[:space:]]*;?$/)
      BRK_PEND = FNR "\t" line_kind() "\t" snippet(r) "\n"
    return
  }
  if (s != "" && s !~ /^(fi|done|esac|\}|\)|;;)/ && BANG_PEND) {
    emit(BANG_KIND, "inert-assertion", BANG_PEND, "a ! command that is not the test's last line never fails it: " BANG_SNIP)
    BANG_PEND = 0
  }
  if (s ~ /^run[[:space:]]/) {
    if (RUN_PEND) emit(RUN_KIND, "inert-assertion", RUN_PEND, "run result never checked: " RUN_SNIP)
    RUN_PEND = 0
    if (s !~ /^run[[:space:]]+(--?[A-Za-z-]+[[:space:]]+)*(!|-[0-9])/) {
      RUN_PEND = FNR; RUN_KIND = line_kind(); RUN_SNIP = snippet(r)
      r = substr(r, index(r, "run") + 3)
    }
  }
  if (RUN_PEND && r ~ /\$\{?(status|output|lines|stderr|stderr_lines)([^A-Za-z0-9_]|$)|(^|[^A-Za-z0-9_])(assert|refute)[A-Za-z_]*/) RUN_PEND = 0
  if (s ~ /^![[:space:]]/) { BANG_PEND = FNR; BANG_KIND = line_kind(); BANG_SNIP = snippet(r); BANG_SOLO = s !~ /\|\||&&|;/ }
}

function inert_close(    n, recs, i, f) {
  if (has(block_masked, R_BODY_SKIP)) RUN_PEND = 0
  if (RUN_PEND) emit(RUN_KIND, "inert-assertion", RUN_PEND, "run result never checked: " RUN_SNIP)
  if (PS_PEND) emit(PS_KIND, "inert-assertion", PS_PEND, PS_DET)
  BANG_LAST = BANG_PEND && BANG_SOLO
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
  if (GO_D <= 0 && has(GO_BUF, R_WEAK)) {
    OR_S = GO_S0
    if (!OR_W++) { OR_WLINE = GO_IF; OR_WSNIP = snippet(GO_BUF) }
  }
  GO_IF = 0
}

function inert_scan(m, r,    s, d) {
  s = trim(m)
  if (LEXER == "bash") { sh_inert(s, r); return }
  if (LEXER == "go") { if (GO_IF || stmt_start()) go_inert(s, m); return }
  if (PS_PEND && s != "") {
    if (s !~ /^\|/) emit(PS_KIND, "inert-assertion", PS_PEND, PS_DET)
    PS_PEND = 0
  }
  if (s == "" || !(SEG_I > 1 || CS_HEAD || stmt_start())) return
  if (LEXER == "pwsh" && depth != 1) return
  d = ""
  if (has(s, R_ASYNC) && !CS_RET) d = "an async assertion nothing awaits never runs before the test ends"
  else if (has(s, R_INERT)) d = "the statement looks like an assertion and asserts nothing"
  else if (LEXER == "python" && s ~ /^assert[[:space:](]/) d = py_assert_inert(r)
  if (d == "") return
  if (LEXER == "pwsh") { PS_PEND = FNR; PS_KIND = line_kind(); PS_DET = d ": " snippet(r) }
  else emit(line_kind(), "inert-assertion", FNR, d ": " snippet(r))
}


function src_const(m, r,    k, p) {
  if (SRC_CN == "") {
    if (!match(m, /^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*(:[^=]*)?=/)) return
    k = substr(m, RSTART, RLENGTH)
    p = k !~ /^[[:space:]]*(export[[:space:]]+)?const[[:space:]]/
    sub(/^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+/, "", k); sub(/[[:space:]]*(:[^=]*)?=$/, "", k)
    if (p) { delete SRC_CONST[k]; return }
    SRC_CN = k; SRC_CL = SRC_CD = 0
    SRC_CM = substr(m, RSTART + RLENGTH); SRC_CR = substr(r, RSTART + RLENGTH)
    m = SRC_CM
  } else { SRC_CM = SRC_CM " " m; SRC_CR = SRC_CR " " r }
  SRC_CD += gsub(/\(/, "(", m) - gsub(/\)/, ")", m)
  if (SRC_CD > 0 && ++SRC_CL < 20) return
  k = SRC_CR
  if ((p = index(SRC_CM, ";"))) k = substr(k, 1, p - 1)
  k = SRC_CD ? "" : arg_path(trim(k))
  if (k != "") SRC_CONST[SRC_CN] = k
  else delete SRC_CONST[SRC_CN]
  SRC_CN = ""
}

function unquote(s) {
  if (s ~ /^@?"[^"]*"$/) { sub(/^@?"/, "", s); sub(/"$/, "", s) }
  else if (s ~ /^'[^']*'$/ || s ~ /^`[^`$]*`$/) s = substr(s, 2, length(s) - 2)
  else return ""
  return s
}

function arg_path(args,    first, p) {
  first = split_top_comma(args) ? trim(SPLIT1) : trim(args)
  if (first in SRC_CONST) return SRC_CONST[first]
  if ((p = unquote(first)) != "") return p
  if (first ~ /^new[[:space:]]+URL[[:space:]]*\(/ && index(first, "import.meta.url")) {
    p = index(first, "(")
    if (extract_parens(first, p) && split_top_comma(EXTRACT)) return unquote(trim(SPLIT1))
    return ""
  }
  if (first ~ /^([A-Za-z_]+\.)?(resolve|join|Join|Combine)[[:space:]]*\(/) {
    p = index(first, "(")
    if (!extract_parens(first, p)) return ""
    return join_literals(EXTRACT)
  }
  return ""
}

function join_literals(args,    out, part, more) {
  out = ""
  for (;;) {
    more = split_top_comma(args)
    part = trim(more ? SPLIT1 : args)
    if (part == "" && !more) break
    if (out == "" && part ~ /^(__dirname|import\.meta\.dirname)$/) part = ""
    else if (part in SRC_CONST) part = SRC_CONST[part]
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
  if (path == "" || path ~ /[*?[]/ || path ~ /^\// || (SHELL_LEX && index(path, "$"))) return
  if (tolower(path) ~ /(^|\/)(tmp|temp|fixtures?|testdata|__fixtures__|__testfixtures__|__snapshots__|snapshots?)(\/|$)/) return
  if (path !~ /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|py|cs|razor|go|sh|bash|ps1|psm1|vue|svelte)$/) return
  SRC_PEND = SRC_PEND line_kind() "\t" FNR "\t" path "\n"
}

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
  if ((LEXER == "js" && match(m, /(^|[^A-Za-z0-9_$])readFile(Sync)?[[:space:]]*\(/)) ||
      (LEXER == "cs" && match(m, /File[[:space:]]*\.[[:space:]]*ReadAll(Text|Lines|Bytes)(Async)?[[:space:]]*\(/)) ||
      (LEXER == "go" && match(m, /(os|ioutil)[[:space:]]*\.[[:space:]]*ReadFile[[:space:]]*\(/))) {
    if (extract_parens(r, RSTART + RLENGTH - 1)) src_emit(arg_path(EXTRACT))
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

function only_calls(m, r, re,    f) {
  if (!has(m, re)) return 0
  f = fill(m, r)
  if (!has(f, re)) return 0
  gsub(re, "", f)
  return !has(f, R_ANY) && !has(f, R_MOCKA)
}

function oracle_line(m, r) {
  if (!has(m, R_ANY) && !has(m, R_MOCKA)) return
  if (LEXER == "cs" && (SEG_I > 1 || CS_HEAD || stmt_start()) && has(trim(m), R_INERT)) return
  if (only_calls(m, r, R_EXISTS)) { exists_add(m, r); return }
  if (LEXER != "go" && only_calls(m, r, R_WEAK)) { if (!OR_W++) { OR_WLINE = FNR; OR_WSNIP = snippet(r) }; return }
  if (only_calls(m, r, R_SNAP) && snap_ok(m)) { if (!OR_P++) OR_PLINE = FNR; return }
  OR_S++
}

function exists_add(m, r,    t) {
  match(m, R_EXISTS)
  t = substr(m, RSTART, RLENGTH)
  EX_N++
  EX_TYPE[EX_N] = match(t, /<[^<>()]*>/) ? norm(substr(t, RSTART + 1, RLENGTH - 2)) : ""
  t = substr(t, index(t, "(") + 1)
  match(t, /[A-Za-z_][A-Za-z0-9_]*/)
  EX_NAME[EX_N] = substr(t, RSTART, RLENGTH)
  EX_WEAK[EX_N] = has(m, R_WEAK)
  EX_LINE[EX_N] = FNR; EX_SNIP[EX_N] = snippet(r)
}

function exists_resolve(    i, rhs, built, ty) {
  for (i = 1; i <= EX_N; i++) {
    rhs = DV_N[BID, EX_NAME[i]] == 1 && DV_END[BID, EX_NAME[i]] ? DV_RHS[BID, EX_NAME[i]] : ""
    sub(/;.*$/, "", rhs)
    built = rhs ~ /^new([[:space:]]+[A-Za-z_][A-Za-z0-9_.<>,?[:space:]]*)?[[:space:]]*(\([^()]*(\([^()]*\)[^()]*)*\))?[[:space:]]*(\{[^{}]*\})?[[:space:]]*$/ && rhs ~ /[)}][[:space:]]*$/
    if (built && EX_TYPE[i] != "") {
      ty = rhs
      sub(/^new[[:space:]]*/, "", ty); sub(/[[:space:]]*[({].*$/, "", ty)
      built = norm(ty) == EX_TYPE[i]
    }
    if (built) { if (!OR_T++) { OR_TLINE = EX_LINE[i]; OR_TSNIP = EX_SNIP[i] } }
    else if (EX_WEAK[i]) { if (!OR_W++) { OR_WLINE = EX_LINE[i]; OR_WSNIP = EX_SNIP[i] } }
    else OR_S++
  }
}

function snap_ok(m) {
  if (LEXER == "cs") return CS_VERIFY
  if (LEXER == "python" && m ~ /(^|[^A-Za-z0-9_.])snapshot([^A-Za-z0-9_]|$)/) return SIG ~ /[(,][[:space:]]*snapshot[[:space:]]*[,:)=]/
  return 1
}


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
    if (LEXER == "cs") { sub(/[[:space:]]*=$/, "", p); p = after_last(p, "[^A-Za-z0-9_]") }
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

function bind_scan(m, r,    s, rl) {
  s = m; sub(/^[[:space:]]+/, "", s)
  if (PM_NAME != "" && s != "") { if (mapped_literal(s)) RES[BID, PM_NAME] = "l"; PM_NAME = "" }
  if (LEXER == "python" ? bracket_depth > 0 : !stmt_start()) return
  rl = r; sub(/^[[:space:]]+/, "", rl)
  if (!assign_of(s, rl)) return
  DV_N[BID, AS_NAME]++
  DV_RHS[BID, AS_NAME] = AS_RHS
  DV_END[BID, AS_NAME] = s ~ /;[[:space:]]*$/
  if (AS_RHS != "") RES[BID, AS_NAME] = literal_rhs(AS_RHS) || mapped_literal(AS_RHS) ? "l" : "r"
  if (LEXER == "js" && AS_RHS ~ /Promise[[:space:]]*\.[[:space:]]*all(Settled)?[[:space:]]*\($/) PM_NAME = AS_NAME
}

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

function ca_class(t, k,    loops, br) {
  if (!has(t, R_ANY) && !has(t, R_MOCKA)) return
  loops = CR_LOOPS + (k == "l"); br = CR_BR + (k == "b")
  if (has(t, R_FAILC) ? loops > 0 : loops + br > 0) { if (!CA_IN++) { CA_LINE = FNR; CA_SNIP = snippet(raw) } }
  else CA_OUT++
}

function loop_kind(name) {
  if (LEXER == "pwsh") name = tolower(name)
  return RES[BID, name] == "r" ? "l" : ""
}

function cond_brace(m,    cdb, s, k, low, pos, pre, post, e) {
  cdb = CD
  CD += brace_delta(m)
  s = trim(m)
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
  if (match(post, /^[[:space:]]*\}/)) { pre = pre substr(post, 1, RLENGTH); post = substr(post, RLENGTH + 1) }
  ca_class(pre, "")
  ca_class(post, k)
  if (brace_delta(post) > 0) cr_push(k, cdb + brace_delta(pre) + 1)
  else if (post ~ /^[[:space:]]*(if|for|foreach|catch)/ ? post ~ /\)[[:space:]]*$/ && delta(post, "(", ")") == 0 : delta(post, "(", ")") > 0) COND_NEXT = k
}

function cond_indent(m,    s, ind, k, e) {
  s = trim(m)
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
  if (!LINE_IN_TEST) return 0
  if (derived_side(a, b) || derived_side(b, a)) {
    if (!in_test) { if (!PROP_TEST) emit(tkind, "recomputed-derived", FNR, DV_DETAIL) }
    else { DP_N++; DP_K[DP_N] = tkind; DP_L[DP_N] = FNR; DP_D[DP_N] = DV_DETAIL }
    return 1
  }
  return 0
}

function prop_scan(bd0) {
  if (in_test || R_PROP == "" || masked ~ /^[[:space:]]*$/) return
  if (masked ~ /^[[:space:]]*[@[]/) { if (masked ~ R_PROP) PROP_PRE = 1 }
  else if (!(LEXER == "python" && bd0 > 0)) PROP_PRE = 0
}



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
  DEF_END = s == "" ? 0 : RSTART + RLENGTH
  return after_last(s, "[^A-Za-z0-9_$]")
}

function helper_scan(m,    name, ind, k, calls) {
  if (m ~ /^[[:space:]]*$/) return
  if (has(m, R_START)) { HK = 0; return }
  ind = indent_of(m)
  name = def_name(m)
  while (HK > 0 && HI[HK] >= ind && (name != "" || m !~ /^[[:space:]]*([])]|\{)/)) HK--
  if (name != "") { HK++; HI[HK] = ind; HD[HK] = ++DEF_N; DEF_NAME[DEF_N] = name; DEF_CLS[DEF_N] = CLS_K ? CLS_NAME[CLS_K] : "" }
  if (HK > 0 && (has(m, R_ANY) || has(m, R_MOCKA) || has(m, R_FAILC) || m ~ /(^|[^A-Za-z0-9_$.])((throw|raise)([^A-Za-z0-9_$]|$)|reject[[:space:]]*\()/))
    for (k = 1; k <= HK; k++) DEF_ASSERTS[HD[k]] = 1
  if (name != "") {
    m = substr(m, DEF_END)
    DEF_ARITY[DEF_N] = -1
    if (LEXER == "cs" && extract_parens("(" m, 1)) DEF_ARITY[DEF_N] = arg_count(EXTRACT)
  }
  if (HK > 0 && (calls = called_names(m)) != "")
    for (k = 1; k <= HK; k++) DEF_CALLS[HD[k]] = DEF_CALLS[HD[k]] calls
  for (k = 1; k <= HK; k++) DEF_SELF[HD[k]] = DEF_SELF[HD[k]] self_arities(m, DEF_NAME[HD[k]])
}

function cls_scan(m,    ind, re) {
  if (m ~ /^[[:space:]]*$/) return
  ind = indent_of(m)
  while (CLS_K > 0 && CLS_I[CLS_K] >= ind && m !~ /^[[:space:]]*([])]|\{)/) CLS_K--
  if (LEXER == "cs") re = "^[[:space:]]*([a-z]+[[:space:]]+)*(class|record|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*"
  else if (LEXER == "python" || LEXER == "js") re = "^[[:space:]]*(export[[:space:]]+(default[[:space:]]+)?)?(abstract[[:space:]]+)?class[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*"
  else return
  if (match(m, re)) { CLS_K++; CLS_I[CLS_K] = ind; CLS_NAME[CLS_K] = after_last(substr(m, RSTART, RLENGTH), "[^A-Za-z0-9_$]") }
}

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

function arg_count(s,    n) {
  if (s ~ /^[[:space:]]*$/) return 0
  n = 1
  while (split_top_comma(s)) { n++; s = SPLIT2 }
  return n
}

function self_arities(m, name,    out, pre, p) {
  out = ""
  while ((p = index(m, name)) > 0) {
    pre = substr(m, 1, p - 1)
    m = substr(m, p + length(name))
    if (pre ~ /[A-Za-z0-9_$]$/) continue
    if (pre ~ /\.[[:space:]]*$/ && pre !~ /(^|[^A-Za-z0-9_$.])(self|this|cls)[[:space:]]*\.[[:space:]]*$/) continue
    if (match(m, /^[[:space:]]*(<[^<>()]*>)?[[:space:]]*\(/) && extract_parens(m, RLENGTH)) out = out " " arg_count(EXTRACT)
  }
  return out
}

function delegates_to_overload(i,    j, a) {
  if (DEF_SELF[i] == "") return 0
  for (j = 1; j <= DEF_N; j++) {
    if (j == i || !(j in DEF_ASSERTS)) continue
    if (DEF_NAME[j] != DEF_NAME[i] || DEF_CLS[j] != DEF_CLS[i]) continue
    if (DEF_ARITY[j] < 0 || DEF_ARITY[i] < 0) return 1
    if (DEF_ARITY[j] == DEF_ARITY[i]) continue
    a = " " DEF_ARITY[j] " "
    if (index(DEF_SELF[i] " ", a)) return 1
  }
  return 0
}

function helper_verdicts(    i, changed, hit) {
  for (i = 1; i <= DEF_N; i++) SCOPE_DEFS[DEF_CLS[i] SUBSEP DEF_NAME[i]]++
  for (i = 1; i <= DEF_N; i++) if (i in DEF_ASSERTS) helper_mark(i)
  do {
    changed = 0
    for (i = 1; i <= DEF_N; i++) {
      if (i in DEF_ASSERTS) continue
      hit = calls_helper(DEF_CALLS[i], DEF_CLS[i])
      if (!hit) hit = delegates_to_overload(i)
      if (hit) { DEF_ASSERTS[i] = 1; helper_mark(i); changed = 1 }
    }
  } while (changed)
}

function eval_block(    blk, stripped, mocka_n, kind, calls) {
  blk = block_masked
  if (has(blk, R_BODY_SKIP)) return
  blocks++
  if (BLOCKS) block_record()
  if (SRC_PEND != "") src_flush()
  g8_eval()
  if (block_raw) return
  kind = block_exempt ? "X" : "F"
  if (!has(blk, R_ANY) && !has(blk, R_MOCKA) && !BANG_LAST) {
    if ((calls = called_names(blk)) == "") emit(kind, "zero-assertion", block_line, "test '" block_name "' has 0 assertion tokens")
    else if (!INVENTORY && !index(RULES_OFF, "|zero-assertion|") && (SCOPE == "" || in_scope(block_line, block_hi))) {
      ZA_N++; ZA_CALLS[ZA_N] = calls; ZA_CLS[ZA_N] = block_cls
      ZA_REC[ZA_N] = sprintf("%s\tzero-assertion\t%d\t%s\n", kind, block_line, clean_detail("test '" block_name "' has 0 assertion tokens"))
    }
    return
  }
  exists_resolve()
  if (OR_W && !OR_S && !OR_P)
    emit(kind, "weak-oracle", OR_WLINE, "test '" block_name "': the only oracle passes for almost any value: " OR_WSNIP)
  if (OR_P && !OR_S && !OR_W)
    emit(kind, "snapshot-only", OR_PLINE, "test '" block_name "': snapshot is the only oracle: review it as code")
  if (OR_T && !OR_S && !OR_W && !OR_P)
    emit(kind, "throw-only-oracle", OR_TLINE, "test '" block_name "': the only oracle checks a value the test constructed, so it fails only if the constructor throws: " OR_TSNIP)
  if (CA_IN && !CA_OUT && blk !~ /(^|[^A-Za-z0-9_$])else([^A-Za-z0-9_$]|$)/ && !has(blk, R_COUNT))
    emit(kind, "conditional-assertion", CA_LINE, "test '" block_name "': every assertion sits inside an if, a catch or a loop over a result, so a path runs none: " CA_SNIP)
  else if (ER_LINE)
    emit(kind, "conditional-assertion", ER_LINE, "test '" block_name "': a return before every assertion ends the test as passed on that path, with nothing asserted: " ER_SNIP)
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
  OR_S = OR_W = OR_P = OR_WLINE = OR_PLINE = OR_T = OR_TLINE = EX_N = 0
  ER_LINE = ER_DONE = ER_D = CW_OPEN = CW_IN = CW_ARM = 0
  CD = CR_N = CR_LOOPS = CR_BR = CA_IN = CA_OUT = CA_LINE = 0
  COND_NEXT = SRC_PEND = SIG = PM_NAME = CS_SIG = ""
  CS_RET = CS_WRAP = CS_HEAD = 0
  SIG_OPEN = PY_HEAD = LEXER == "python"
  PY_D = SP_D = SP_K = 0
  SH_ACT = SH_FN = PS_PEND = 0
  PROP_TEST = PROP_PRE; PROP_PRE = DP_N = 0
}

function split_stmts(m, r,    n, i, c, from, k) {
  SEG_N = 0
  n = length(m)
  if (LEXER != "cs" && LEXER != "js" && LEXER != "python" && LEXER != "bash") { seg_add(m, r, 1, n); return }
  from = 1; k = 0
  for (i = 1; i <= n; i++) {
    c = substr(m, i, 1)
    if (c == "(" || c == "[") SP_D++
    else if (c == ")" || c == "]") { if (SP_D > 0) SP_D-- }
    else if (c == "{") { SP_S[++SP_K] = SP_D; SP_D = 0 }
    else if (c == "}") SP_D = SP_K > 0 ? SP_S[SP_K--] : 0
    else if (c == ";" && SP_D == 0) {
      if (LEXER == "bash" && substr(m, i + 1, 1) ~ /[;&]/) { i++; continue }
      SP_A[++k] = from; SP_B[k] = LEXER == "cs" || LEXER == "js" ? i : i - 1
      from = i + 1
    }
  }
  SP_A[++k] = from; SP_B[k] = n
  if (k <= 16) for (i = 1; i <= k; i++) seg_add(m, r, SP_A[i], SP_B[i])
  if (!SEG_N) seg_add(m, r, 1, n)
}

function er_scan(m, r,    d0, p, a, cw, post) {
  if (LEXER != "cs" || ER_DONE) return
  d0 = ER_D
  ER_D += brace_delta(m)
  if (CW_ARM && m !~ /^[[:space:]]*$/) { if (m !~ /^[[:space:]]*\{/) CW_OPEN = 0; CW_ARM = 0 }
  if (CW_OPEN) { if (d0 >= CW_OPEN) CW_IN = 1; else if (CW_IN) CW_OPEN = CW_IN = 0 }
  p = match(m, /(^|[^A-Za-z0-9_.])return[[:space:]]*;/) ? RSTART + RLENGTH : 0
  a = 0
  if (match(m, R_ANY)) a = RSTART
  if (R_MOCKA != "" && match(m, R_MOCKA) && (!a || RSTART < a)) a = RSTART
  cw = 0
  if (match(m, /(^|[^A-Za-z0-9_])catch([[:space:](].*)?[[:space:])]when[[:space:]]*\(/) ||
    match(m, /=>[[:space:]]*(\{|$)/) ||
    (m !~ /^[[:space:]]*(return|await|throw|yield|new|else|case|goto)([^A-Za-z0-9_]|$)/ && m !~ /;[[:space:]]*$/ &&
      match(m, /^[[:space:]]*((static|async|unsafe)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.?]*(\[\])*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(<[^<>()]*>)?[[:space:]]*\(/))) {
    cw = RSTART
    post = substr(m, cw)
    if (!index(post, "{") || brace_delta(post) > 0) {
      CW_OPEN = d0 + brace_delta(substr(m, 1, cw - 1)) + 1
      CW_IN = brace_delta(post) > 0
      CW_ARM = !index(post, "{")
    }
  }
  if (p && (!a || p < a) && !CW_IN && !(cw && cw < p)) { ER_LINE = FNR; ER_SNIP = snippet(r); ER_DONE = 1 }
  if (a) ER_DONE = 1
}

function seg_add(m, r, a, b,    n) {
  n = length(m)
  if (a == 1 && b >= n) { SEG_N++; SEG_M[SEG_N] = m; SEG_R[SEG_N] = r; return }
  if (b < a || substr(m, a, b - a + 1) ~ /^[[:space:]]*$/) return
  SEG_N++
  SEG_M[SEG_N] = blanks(a - 1) substr(m, a, b - a + 1) blanks(n - b)
  SEG_R[SEG_N] = blanks(a - 1) substr(r, a, b - a + 1) blanks(n - b)
}

function append_block(m, r,    bm, br) {
  bm = m; br = r
  CS_HEAD = CS_WRAP && m !~ /^[[:space:]]*$/
  if (CS_HEAD) CS_WRAP = 0
  if (LEXER == "cs" && !body_open && !expr_body) { cs_cut(m, r); bm = CUT_M; br = CUT_R }
  else if (PY_HEAD || (LEXER == "go" && FNR == block_line)) {
    decl_cut(m, r); bm = CUT_M; br = CUT_R
    if (has(bm, R_MOCKC)) file_mock = 1
  }
  block_masked = block_masked bm "\n"
  block_last = FNR
  LINE_IN_TEST = 1
  if (!PROP_TEST && has(m, R_PROP)) PROP_TEST = 1
  if (SIG_OPEN) { SIG = SIG " " m; if (index(SIG, "(") && delta(SIG, "(", ")") <= 0) SIG_OPEN = 0 }
  if (r ~ R_EXEMPT) block_exempt = 1
  if (R_RAW != "" && !block_raw) {
    if ((BW2 "\n" BW1 "\n" br) ~ R_RAW) block_raw = 1
    BW2 = BW1; BW1 = br
  }
  OR_S0 = OR_S
  split_stmts(bm, br)
  if (FNR != block_line || LEXER != "bash")
    for (SEG_I = 1; SEG_I <= SEG_N; SEG_I++) oracle_line(SEG_M[SEG_I], SEG_R[SEG_I])
  SEG_I = 0
  if (LEXER != "bash") { cond_scan(m); bind_scan(m, r) }
  else sh_act_scan(m)
  if (FNR != block_line || LEXER == "cs" || LEXER == "python" || LEXER == "go")
    for (SEG_I = 1; SEG_I <= SEG_N; SEG_I++) inert_scan(SEG_M[SEG_I], SEG_R[SEG_I])
  SEG_I = 0
  er_scan(bm, br)
  src_scan(m, r)
  if (LEXER == "js" || LEXER == "python") g8_bind(m, r)
  if (m !~ /^[[:space:]]*$/) { prev_code = code_tail(m, r); block_code_last = FNR }
}

function close_block(    i) {
  in_test = 0
  block_hi = MODEL == "indent" ? block_last : FNR
  closed_lo = block_line; closed_at = FNR
  if (PEND != "" && in_scope(block_line, block_hi)) printf "%s", PEND
  PEND = ""
  ORD[block_name]++
  closing = 1; inert_close()
  if (!PROP_TEST) for (i = 1; i <= DP_N; i++) emit(DP_K[i], "recomputed-derived", DP_L[i], DP_D[i])
  DP_N = 0
  eval_block(); closing = 0
}

function block_record(    hi) {
  hi = MODEL == "indent" ? block_code_last : block_hi
  if (SCOPE == "" || in_scope(block_line, hi))
    printf "K\t%d-%d\t%d\t%s\n", block_line, hi, ORD[block_name], clean_detail(block_name)
}

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

function cs_cut(m, r,    i, j, k, n) {
  i = index(m, "{"); j = index(m, "=>")
  k = (j && (!i || j < i)) ? j : i
  if (!k) { CS_SIG = CS_SIG " " m; CUT_M = blanks(length(m)); CUT_R = blanks(length(r)); return }
  CS_SIG = CS_SIG " " substr(m, 1, k - 1)
  n = k == j ? k + 1 : k
  CUT_M = blanks(n) substr(m, n + 1)
  CUT_R = blanks(n) substr(r, n + 1)
  if (k == j) {
    CS_RET = CS_SIG ~ /(^|[^A-Za-z0-9_.]|System\.Threading\.Tasks\.)(Task|ValueTask)([^A-Za-z0-9_]|$)/ && CS_SIG !~ /(^|[^A-Za-z0-9_])async([^A-Za-z0-9_]|$)/
    CS_WRAP = substr(CUT_M, n + 1) ~ /^[[:space:]]*$/
    return
  }
  if (brace_delta(m) <= 0) cut_last_brace(n)
}

function cut_last_brace(k,    i) {
  for (i = length(CUT_M); i > k; i--) if (substr(CUT_M, i, 1) == "}") break
  if (i > k) { CUT_M = substr(CUT_M, 1, i - 1) " " substr(CUT_M, i + 1); CUT_R = substr(CUT_R, 1, i - 1) " " substr(CUT_R, i + 1) }
}

function decl_cut(m, r,    i, n, c, k, d) {
  n = length(m); k = n; d = 0
  for (i = 1; i <= n; i++) {
    c = substr(m, i, 1)
    if (LEXER == "python") {
      if (c == "(" || c == "[" || c == "{") PY_D++
      else if (c == ")" || c == "]" || c == "}") PY_D--
      else if (c == ":" && PY_D <= 0) { k = i; PY_HEAD = 0; break }
    } else if (c == "(") d++
    else if (c == ")") d--
    else if (c == "{" && d == 0) { k = i; break }
  }
  CUT_M = blanks(k) substr(m, k + 1)
  CUT_R = blanks(k) substr(r, k + 1)
  if (LEXER == "go" && brace_delta(m) <= 0) cut_last_brace(k)
}

function cs_method_name(s) {
  sub(/\(.*$/, "", s)
  if (!match(s, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) return "(unnamed)"
  s = substr(s, RSTART, RLENGTH)
  gsub(/[[:space:]]/, "", s)
  return s
}


function brace_call() {
  if (in_test) {
    append_block(masked, raw)
    depth += brace_delta(masked)
    call_depth += delta(masked, "(", ")")
    if (depth <= 0 && call_depth <= 0) close_block()
    taut_scan(raw, masked)
  } else if (sr) {
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

function whole_file(    n, parts) {
  if (!in_test) {
    n = split(FILENAME, parts, "/")
    open_block(FNR, parts[n])
  }
  append_block(masked, raw)
  taut_scan(raw, masked)
}

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

function brace_decl() {
  if (pending_skip && masked ~ /(^|[^A-Za-z0-9_])class[[:space:]]/) {
    sr = 1; sr_open = sr_depth = pending_attr = pending_skip = 0
  }
  if (sr) {
    sr_depth += brace_delta(masked)
    if (index(masked, "{")) sr_open = 1
    if (sr_open && sr_depth <= 0) sr = 0
  } else if (in_test) {
    append_block(masked, raw)
    if (expr_body) {
      if (masked ~ /;[[:space:]]*$/) { expr_body = 0; close_block() }
    } else if (body_open) {
      depth += brace_delta(masked)
      if (depth <= 0) close_block()
    } else cs_body_start(masked)
  } else if (pending_attr && masked ~ /(public|private|protected|internal|async|static|void|Task)[^=]*\(/ && masked !~ /^[[:space:]]*\[/) {
    pending_attr = 0
    if (pending_skip) pending_skip = 0
    else {
      open_block(FNR, cs_method_name(masked))
      body_open = 0; expr_body = 0; depth = 0
      append_block(masked, raw)
      cs_body_start(masked)
    }
  } else {
    if (has(masked, R_START)) {
      pending_attr = 1
      if (has(masked, R_SKIP)) pending_skip = 1
    } else if (masked ~ /^[[:space:]]*\[/) {
      if (has(masked, R_SKIP)) pending_skip = 1
    } else if (masked !~ /^[[:space:]]*$/) { pending_attr = 0; pending_skip = 0 }
  }
  taut_scan(raw, masked)
}


{
  raw = $0
  sub(/\r$/, "", raw)
  if (LEXER == "js") masked = mask_js(raw)
  else if (LEXER == "python") masked = mask_py(raw)
  else if (LEXER == "bash") masked = mask_sh(raw)
  else if (LEXER == "pwsh") masked = mask_ps(raw)
  else if (LEXER == "go") masked = mask_go(raw)
  else masked = mask_cs(raw)

  if (has(masked, R_MOCKC) && !((LEXER == "python" || LEXER == "go") && has(masked, R_START))) file_mock = 1
  if (INVENTORY) inv_line()
  LINE_IN_TEST = 0
  if (SHELL_LEX) sh_assign(masked)
  if (LEXER == "bash") sh_file_facts()

  if (!SHELL_LEX) cls_scan(masked)
  if (LEXER == "js") src_const(masked, raw)
  bd0 = bracket_depth
  if (MODEL == "file") whole_file()
  else if (MODEL == "indent") indent()
  else if (LEXER == "cs") brace_decl()
  else brace_call()
  if (!LINE_IN_TEST && !SHELL_LEX) helper_scan(masked)
  prop_scan(bd0)
  prev_raw = raw
}

END {
  if (FATAL) exit 2
  if (INVENTORY && (mask_open() || S_bc || S_tpl || S_triple || S_verb)) print INVENTORY "\tunjudged"
  else if (mask_open()) print "L\t1"
  else if (in_test) close_block()
  helper_verdicts()
  for (i = 1; i <= ZA_N; i++) if (!calls_helper(ZA_CALLS[i], ZA_CLS[i])) printf "%s", ZA_REC[i]
  if (!INVENTORY) printf "B\t%d\n", blocks
}
