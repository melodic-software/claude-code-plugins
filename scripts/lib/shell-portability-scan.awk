BEGIN {
  SQ = "\047"; DQ = "\042"; BS = "\134"; BT = "\140"; NL = "\012"
  AMPTOK = "!subst-replacement-ampersand"
  SEPS = ";&|()" NL BT
  QRUN = "(\\$?[" SQ DQ "]|" BS BS ")*"
  STATNAME = "s" QRUN "t" QRUN "a" QRUN "t"
  ASSIGN = "(([A-Za-z_][A-Za-z0-9_]*=[^;|&[:space:]]*|[0-9]*[<>][<>]?&?[[:space:]]*[^;|&[:space:]]*)[[:space:]]+)*"
  PREFIXES = ASSIGN "((command|env)[[:space:]]+)?" ASSIGN "(\\\\)?[[:space:]]*"
  WORDSTART = " \t;&|()" NL BT
  NEGOPEN = "(([A-Za-z_][A-Za-z0-9_]*=)?(\\$\\(|" BT "|\\()[[:space:]]*)*"
  SEG = "([^;|&" NL "]|[<>]&|&>|&&)*"
  CMDPOS = "\\|\\|[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=)?(\\$\\(|" BT "|\\(|\\{[[:space:]])?[[:space:]]*" PREFIXES
  NAME = "(\\$?[" SQ DQ "]|" BS BS ")?" "(/[^;|&[:space:]]*/)?"
  PRE = "(\\$?[" SQ DQ "]|" BS BS ")?" "[[:space:]]+([^;|&\n]*[[:space:]])?"
  QL = "([A-Za-z]|\\$?[" SQ DQ "]|" BS BS ")*"
  READLINK_LADDER = "realpath" SEG CMDPOS NAME "readlink$"
  STAT_LADDER = "^" STATNAME PRE QRUN "(-" QL "c|--format|--printf)" SEG CMDPOS NAME STATNAME PRE QRUN "-" QL "f"
}
function is_annotated(l) { return l ~ /portability-ok:/ }
function is_comment(l) { return l ~ /^[[:space:]]*#/ }
function mq_hold(st,   d) {
  HELD_ST = st
  HELD_CMT = MQ_CMT
  HELD_NV = NV
  for (d = 1; d <= length(st); d++) {
    HELD_AR[d] = ARDEPTH[d]
    HELD_VO[d] = VOPEN[d]
  }
}
function mq_resume(   d) {
  MQ_CMT = HELD_CMT
  NV = HELD_NV
  for (d = 1; d <= length(HELD_ST); d++) {
    ARDEPTH[d] = HELD_AR[d]
    VOPEN[d] = HELD_VO[d]
  }
}
function mq_reset() {
  HELD_ST = "U"
  HELD_CMT = 0
  HELD_NV = 0
  MQ_POS = 0
  MQ_MASK = ""
  MQ_TAIL = ""
}
function mask_full() { return MQ_MASK MQ_TAIL }
function mask_quotes(l,   i, c, m, st, top, len, climit, held) {
  mq_resume()
  st = HELD_ST
  m = ""
  DANGLING_BS = 0
  DANGLING_QUOTE = 0
  len = length(l)
  climit = len - 2 - (substr(l, len, 1) == BS)
  held = 0
  for (i = MQ_POS + 1; i <= len; i++) {
    if (!held && i > climit) {
      MQ_MASK = MQ_MASK m
      MQ_POS = i - 1
      mq_hold(st)
      m = ""
      held = 1
    }
    if (MQ_CMT) {
      m = m "Q"
      continue
    }
    c = substr(l, i, 1)
    top = substr(st, length(st), 1)
    if (top == "S") {
      m = m "Q"
      if (c == SQ) st = substr(st, 1, length(st) - 1)
      continue
    }
    if (c == BS) {
      m = m "Q"
      if (i < len) { m = m "Q"; i++ }
      else DANGLING_BS = 1
      continue
    }
    if (c == BT) {
      m = m c
      if (top == "B") st = substr(st, 1, length(st) - 1)
      else st = st "B"
      continue
    }
    if (c == "$" && substr(l, i + 1, 1) == "(" && substr(l, i + 2, 1) == "(") {
      m = m "QQQ"
      st = st "A"
      ARDEPTH[length(st)] = 0
      i += 2
      continue
    }
    if (c == "$" && substr(l, i + 1, 1) == "(") {
      m = m "Q("
      st = st "P"
      i++
      continue
    }
    if (c == "$" && substr(l, i + 1, 1) == "{") {
      m = m "QQ"
      st = st "V"
      VOPEN[length(st)] = i
      i++
      continue
    }
    if (top == "A") {
      m = m "Q"
      if (c == "(") ARDEPTH[length(st)]++
      else if (c == ")") {
        if (ARDEPTH[length(st)] > 0) ARDEPTH[length(st)]--
        else if (substr(l, i + 1, 1) == ")") {
          m = m "Q"
          st = substr(st, 1, length(st) - 1)
          i++
        }
      }
      continue
    }
    if (top == "V") {
      m = m "Q"
      if (c == SQ) st = st "S"
      else if (c == DQ) st = st "D"
      else if (c == "}") {
        NV++
        VS[NV] = VOPEN[length(st)]
        VE[NV] = i
        st = substr(st, 1, length(st) - 1)
      }
      continue
    }
    if (top == "D") {
      m = m "Q"
      if (c == DQ) st = substr(st, 1, length(st) - 1)
      continue
    }
    if (c == "#" && (i == 1 || index(WORDSTART, substr(l, i - 1, 1)) > 0)) {
      MQ_CMT = 1
      m = m "Q"
      continue
    }
    if (c == SQ) { m = m "Q"; st = st "S"; continue }
    if (c == DQ) { m = m "Q"; st = st "D"; continue }
    if (c == "(") { m = m c; st = st "G"; continue }
    if (c == ")" && (top == "P" || top == "G")) {
      m = m c
      st = substr(st, 1, length(st) - 1)
      continue
    }
    m = m c
  }
  DANGLING_QUOTE = (length(st) > 1)
  if (!held) {
    MQ_MASK = MQ_MASK m
    MQ_POS = len
    mq_hold(st)
    m = ""
  }
  MQ_TAIL = m
}
function neutralize(l, m,   i, c, r, out, len) {
  r = ""
  out = ""
  len = length(l)
  for (i = 1; i <= len; i++) {
    if (length(r) >= 4096) {
      out = out r
      r = ""
    }
    c = substr(l, i, 1)
    if (substr(m, i, 1) == "Q" && c == NL) r = r " "
    else if (substr(m, i, 1) == "Q" && index(SEPS, c) > 0) r = r "Q"
    else r = r c
  }
  return out r
}
function collapse_subs(q, m,   i, c, r, out, len, kinds, nc, inbt, prev, top) {
  r = ""
  out = ""
  kinds = ""
  nc = 0
  inbt = 0
  len = length(m)
  for (i = 1; i <= len; i++) {
    if (length(r) >= 4096) {
      out = out r
      r = ""
    }
    c = substr(m, i, 1)
    if (c == BT) {
      inbt = !inbt
      r = r "~"
      continue
    }
    if (c == "(") {
      prev = ""
      if (i > 1) prev = substr(m, i - 1, 1)
      if (prev == "<" || prev == ">") {
        kinds = kinds "S"
      } else {
        kinds = kinds "C"
        nc++
      }
    } else if (c == ")" && kinds != "") {
      top = substr(kinds, length(kinds), 1)
      if (nc > 0 || inbt) r = r "~"
      else r = r substr(q, i, 1)
      if (top == "C") nc--
      kinds = substr(kinds, 1, length(kinds) - 1)
      continue
    }
    if (nc > 0 || inbt) r = r "~"
    else r = r substr(q, i, 1)
  }
  return out r
}
function is_wordbreak(mc) { return index(" \t;&|()<>" NL BT, mc) > 0 }
function skip_redirection(m, at, limit) {
  while (at <= limit && substr(m, at, 1) ~ /[<>&]/) at++
  while (at <= limit && substr(m, at, 1) ~ /[ \t]/) at++
  while (at <= limit && !is_wordbreak(substr(m, at, 1))) at++
  return at
}
function word_start(m, pos,   i) {
  for (i = pos; i > 1; i--)
    if (is_wordbreak(substr(m, i - 1, 1))) return i
  return 1
}
function word_end(m, pos,   i, len) {
  len = length(m)
  for (i = pos; i < len; i++)
    if (is_wordbreak(substr(m, i + 1, 1))) return i
  return len
}
function unquote_word(w,   i, c, n, st, r, len) {
  r = ""
  st = "U"
  len = length(w)
  for (i = 1; i <= len; i++) {
    c = substr(w, i, 1)
    if (st == "S") {
      if (c == SQ) st = "U"
      else r = r c
      continue
    }
    if (st == "D") {
      if (c == DQ) { st = "U"; continue }
      if (c == BS) {
        n = substr(w, i + 1, 1)
        if (n == DQ || n == "$" || n == BT || n == BS) { r = r n; i++ }
        else r = r c
        continue
      }
      r = r c
      continue
    }
    if (c == "$" && (substr(w, i + 1, 1) == SQ || substr(w, i + 1, 1) == DQ)) continue
    if (c == SQ) { st = "S"; continue }
    if (c == DQ) { st = "D"; continue }
    if (c == BS) { i++; if (i <= len) r = r substr(w, i, 1); continue }
    r = r c
  }
  return r
}
function dashdash_between(view, m, from, to,   i, c, w, tainted, depth) {
  w = ""
  tainted = 0
  for (i = from; i <= to; i++) {
    c = substr(m, i, 1)
    if (c == "<" || c == ">" || (c == "&" && substr(m, i + 1, 1) == ">")) {
      w = ""
      tainted = 0
      i = skip_redirection(m, i, to) - 1
      continue
    }
    if (c == ";" || c == "&" || c == "|" || c == NL) return 0
    if (c == "(") {
      depth = 1
      while (i < to && depth > 0) {
        i++
        c = substr(m, i, 1)
        if (c == "(") depth++
        else if (c == ")") depth--
      }
      if (depth > 0) return 0
      tainted = 1
      continue
    }
    if (c == BT) {
      i++
      while (i <= to && substr(m, i, 1) != BT) i++
      if (i > to) return 0
      tainted = 1
      continue
    }
    if (c == ")") return 0
    if (is_wordbreak(c)) {
      if (w != "" && !tainted && unquote_word(w) == "--") return 1
      w = ""
      tainted = 0
      continue
    }
    w = w substr(view, i, 1)
  }
  if (w != "" && !tainted && unquote_word(w) == "--") return 1
  return 0
}
function dashdash_demoted(view, m, at, mend,   ce, pe, os, oe) {
  pe = mend
  while (pe > at && is_wordbreak(substr(m, pe, 1))) pe--
  ce = word_end(m, at)
  if (pe <= ce) return 0
  os = word_start(m, pe)
  if (os <= ce + 1) return 0
  oe = word_end(m, pe)
  if (unquote_word(substr(view, os, oe - os + 1)) !~ /^-/) return 0
  DD_OS = os
  return dashdash_between(view, m, ce + 1, os - 1)
}
function fallback_proven(q, m, opos, os, oe,   i, c, w, uw, phase, j, wantarg) {
  phase = 0
  wantarg = 0
  w = ""
  i = opos + 2
  while (i < os) {
    c = substr(m, i, 1)
    if (c == "<" || c == ">" || (c == "&" && substr(m, i + 1, 1) == ">")) {
      w = ""
      i = skip_redirection(m, i, os - 1)
      continue
    }
    if (is_wordbreak(c)) {
      if (w != "") {
        uw = unquote_word(w)
        if (wantarg) {
          wantarg = 0
        } else if (uw == "--") return 0
        else if (phase == 0) {
          if (uw ~ /(^|\/)stat$/) phase = 1
        } else if (uw !~ /^-/) return 0
        else if (uw ~ /^-[FHhLlnqrsx]*[ft]$/) wantarg = 1
      }
      w = ""
      i++
      continue
    }
    w = w substr(q, i, 1)
    i++
  }
  if (wantarg) return 0
  uw = unquote_word(substr(q, os, oe - os + 1))
  if (uw !~ /^-[FHhLlnqrsx]*f/) return 0
  if (substr(uw, index(uw, "f") + 1) != "") return 1
  j = oe + 1
  while (substr(m, j, 1) ~ /[ \t]/) j++
  c = substr(m, j, 1)
  if (c == "" || substr(q, j, 1) == "#" || index(";&|)" NL BT, c) > 0) return 0
  return 1
}
function blanks(n) {
  if (n <= 0) return ""
  if (PAD == "") PAD = " "
  while (length(PAD) < n) PAD = PAD PAD
  return substr(PAD, 1, n)
}
function after_last_boundary(h,   part, n) {
  n = split(h, part, "[;|&)" NL "]")
  if (n == 0) return ""
  return part[n]
}
function is_negated(q, at,   head) {
  head = after_last_boundary(substr(q, 1, at - 1))
  if (head !~ /![[:space:]]/) return 0
  return head ~ ("(^|[[:space:]]|[(]|" BT ")![[:space:]]+" NEGOPEN PREFIXES "$")
}
function status_swallowed(q, at, m,   head, before, opener, i, c, depth, len, closed) {
  head = after_last_boundary(substr(q, 1, at - 1))
  if (index(head, "$(") == 0 && index(head, BT) == 0) return 0
  if (!match(head, ".*(\\$\\(|" BT ")")) return 0
  before = substr(head, 1, RLENGTH)
  opener = substr(before, length(before), 1)
  sub("(\\$\\(|" BT ")$", "", before)
  if (before !~ "^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=)?[[:space:]]*$") return 1
  len = length(m)
  closed = 0
  if (opener == BT) {
    for (i = at; i <= len; i++) {
      if (substr(m, i, 1) == BT) { closed = i; break }
    }
  } else {
    depth = 1
    for (i = at; i <= len; i++) {
      c = substr(m, i, 1)
      if (c == "(") depth++
      else if (c == ")") {
        depth--
        if (depth == 0) { closed = i; break }
      }
    }
  }
  if (closed == 0) return 0
  for (i = closed + 1; i <= len; i++) {
    c = substr(m, i, 1)
    if (c == "(" || c == BT) return 1
    if (c == ";" || c == "|" || c == "&") return 0
  }
  return 0
}
function is_guarded(q, p, at, m,   lend, opos, os, i, ladder, bar, past) {
  if (is_negated(q, at)) return 0
  if (p ~ /readlink/) return substr(q, 1, at + 7) ~ READLINK_LADDER
  if (index(p, STATNAME) || index(p, "stat")) {
    if (status_swallowed(q, at, m)) return 0
    ladder = substr(q, at)
    bar = index(ladder, "|")
    if (bar == 0 || substr(ladder, bar + 1, 1) != "|") return 0
    past = index(substr(ladder, bar + 2), "|")
    if (past > 0) ladder = substr(ladder, 1, bar + past)
    if (!match(ladder, STAT_LADDER)) return 0
    lend = at + RLENGTH - 1
    opos = 0
    for (i = at; i < lend; i++)
      if (substr(m, i, 1) == "|" && substr(m, i + 1, 1) == "|") { opos = i; break }
    if (opos == 0) return 0
    os = word_start(m, lend)
    return fallback_proven(q, m, opos, os, word_end(m, lend))
  }
  return 0
}
function has_unguarded(view, q, p, m, from,   scan, st, len, at) {
  scan = view
  if (from > 1) scan = blanks(from - 1) substr(view, from)
  while (match(scan, p)) {
    st = RSTART
    len = RLENGTH
    at = st
    if (substr(scan, at, 1) !~ /[A-Za-z]/) at++
    if (dashdash_demoted(view, m, at, st + len - 1)) {
      scan = substr(scan, 1, DD_OS - 1) blanks(st + len - DD_OS) substr(scan, st + len)
      continue
    }
    if (!is_guarded(q, p, at, m)) return at
    scan = substr(scan, 1, st - 1) blanks(len) substr(scan, st + len)
  }
  return 0
}
function opens_frame(l, at,   c, n) {
  c = substr(l, at, 1)
  if (c == BT) return 1
  n = substr(l, at + 1, 1)
  if (c == "$" && (n == "(" || n == "{")) return 1
  if ((c == "<" || c == ">") && n == "(") return 1
  return 0
}
function skip_frame(l, at, limit,   c, o, cl, depth, st) {
  c = substr(l, at, 1)
  if (c == BT) {
    at++
    while (at <= limit && substr(l, at, 1) != BT) at++
    return at + 1
  }
  o = substr(l, at + 1, 1)
  if (o == "(") cl = ")"
  else cl = "}"
  at += 2
  depth = 1
  st = "U"
  while (at <= limit && depth > 0) {
    c = substr(l, at, 1)
    if (st == "S") {
      if (c == SQ) st = "U"
    } else if (c == BS) {
      at++
    } else if (c == SQ) {
      st = "S"
    } else if (c == DQ) {
      if (st == "D") st = "U"
      else st = "D"
    } else if (c == o) {
      depth++
    } else if (c == cl) {
      depth--
    }
    at++
  }
  return at
}
function amp_in_frame(l, s, e,   i, c, sep, named) {
  i = s + 2
  if (i > e - 1) return 0
  c = substr(l, i, 1)
  named = 1
  if (c == "#") {
    if (substr(l, i + 1, 1) != "/") return 0
    i++
    named = 0
  } else if (c == "!") i++
  if (named) {
    c = substr(l, i, 1)
    if (c ~ /[A-Za-z_]/) {
      while (i < e && substr(l, i, 1) ~ /[A-Za-z0-9_]/) i++
    } else if (c ~ /[0-9]/) {
      while (i < e && substr(l, i, 1) ~ /[0-9]/) i++
    } else if (c ~ /[@*?$!-]/) {
      i++
    } else return 0
  }
  if (substr(l, i, 1) == "[") {
    sep = 1
    i++
    while (i < e && sep > 0) {
      c = substr(l, i, 1)
      if (c == "[") sep++
      else if (c == "]") sep--
      i++
    }
    if (sep > 0) return 0
  }
  if (substr(l, i, 1) != "/") return 0
  i++
  c = substr(l, i, 1)
  if (c == "/" || c == "#" || c == "%") i++
  sep = first_unquoted(l, i, e - 1, "/")
  if (sep == 0) return 0
  return first_unquoted(l, sep + 1, e - 1, "&")
}
function first_unquoted(l, i, lim, target,   st, c) {
  st = "U"
  while (i <= lim) {
    c = substr(l, i, 1)
    if (st == "S") {
      if (c == SQ) st = "U"
      i++
      continue
    }
    if (c == BS) { i += 2; continue }
    if (c == SQ) { st = "S"; i++; continue }
    if (c == DQ) {
      if (st == "D") st = "U"
      else st = "D"
      i++
      continue
    }
    if (opens_frame(l, i)) {
      i = skip_frame(l, i, lim)
      continue
    }
    if (st == "U" && c == target) return i
    i++
  }
  return 0
}
function subst_amp_hit(l, from,   f, at, best) {
  best = 0
  for (f = 1; f <= NV; f++) {
    at = amp_in_frame(l, VS[f], VE[f])
    if (at >= from && at > 0 && (best == 0 || at < best)) best = at
  }
  return best
}
function heredoc_delim(l, m,   i, len, j, c, d, q) {
  len = length(m)
  for (i = 1; i < len; i++) {
    if (substr(m, i, 1) != "<" || substr(m, i + 1, 1) != "<") continue
    if (substr(m, i + 2, 1) == "<") { i += 2; continue }
    j = i + 2
    HD_STRIP = 0
    if (substr(l, j, 1) == "-") { HD_STRIP = 1; j++ }
    while (substr(l, j, 1) == " " || substr(l, j, 1) == "\t") j++
    q = ""
    if (substr(l, j, 1) == SQ || substr(l, j, 1) == DQ) { q = substr(l, j, 1); j++ }
    d = ""
    while (j <= length(l)) {
      c = substr(l, j, 1)
      if (q != "" && c == q) break
      if (q == "" && index(" \t;&|<>()" BT, c) > 0) break
      d = d c
      j++
    }
    if (d != "") return d
  }
  return ""
}
function phys_of(off,   k) {
  for (k = nphys; k >= 1; k--)
    if (off >= physoff[k]) return k
  return 1
}
function phys_text(k) {
  if (k >= nphys) return substr(logical, physoff[k])
  return substr(logical, physoff[k], physoff[k + 1] - physoff[k] - 1)
}
FNR == NR {
  line = $0
  if (substr(line, 1, 1) == "!") {
    if (line == AMPTOK) { CLS_AMP = 1; ncls++; next }
    printf "Error: unknown script-implemented class in token list: %s\n", line > "/dev/stderr"
    FATAL = 1
    exit 2
  }
  patterns[++np] = line
  next
}
function scan_logical(line, lineno, mask,   is_cmt, annotated_above, qline, cline, i) {
  is_cmt = is_comment(line)
  annotated_above = pending_annot
  if (is_cmt) {
    if (is_annotated(line)) pending_annot = 1
  } else {
    pending_annot = 0
  }
  if (is_cmt) return
  qline = neutralize(line, mask)
  cline = collapse_subs(qline, mask)
  if (!joined && (is_annotated(line) || annotated_above)) return
  for (i = 1; i <= np; i++) {
    if (report_hit(line, lineno, patterns[i], annotated_above,
      has_unguarded(qline, qline, patterns[i], mask, 1), qline, qline, mask, "ere")) continue
    report_hit(line, lineno, patterns[i], annotated_above,
      has_unguarded(cline, qline, patterns[i], mask, 1), cline, qline, mask, "ere")
  }
  if (CLS_AMP)
    report_hit(line, lineno, AMPTOK, annotated_above,
      subst_amp_hit(line, 1), line, qline, mask, "amp")
}
function next_hit(kind, view, q, p, m, from) {
  if (kind == "amp") return subst_amp_hit(view, from)
  return has_unguarded(view, q, p, m, from)
}
function report_hit(line, lineno, p, annotated_above, off, view, q, m, kind,   k, t) {
  if (!joined) {
    if (off > 0) { hits[++nhits] = sprintf("%d: %s -> %s", lineno, p, line); return 1 }
    return 0
  }
  while (off > 0) {
    k = phys_of(off)
    t = phys_text(k)
    if (!is_comment(t) &&
      !is_annotated(t) &&
      !annot_block_above(k, annotated_above)) {
      hits[++nhits] = sprintf("%d: %s -> %s", physno[k], p, t)
      return 1
    }
    off = next_hit(kind, view, q, p, m, off + 1)
  }
  return 0
}
function annot_block_above(k, annotated_above,   j, t) {
  for (j = k - 1; j >= 1; j--) {
    t = phys_text(j)
    if (!is_comment(t)) return 0
    if (is_annotated(t)) return 1
  }
  return annotated_above
}
{
  if (in_heredoc) {
    body = $0
    if (hd_strip) sub(/^\t+/, "", body)
    if (body == hd_delim) in_heredoc = 0
  } else if (!pending && $0 ~ /^[[:space:]]*#[[:space:]]*portability-scope:/) {
    SCOPED = 1
  }
  if (pending) {
    logical = logical pendsep $0
  } else {
    logical = $0
    logical_line = FNR
    nphys = 0
    joined = 0
    pending = 1
    mq_reset()
  }
  physoff[++nphys] = length(logical) - length($0) + 1
  physno[nphys] = FNR
  mask_quotes(logical)
  if (DANGLING_BS && !is_comment(logical)) {
    logical = substr(logical, 1, length(logical) - 1)
    pendsep = ""
    next
  }
  if (DANGLING_QUOTE && !is_comment(logical) && !in_heredoc) {
    pendsep = NL
    joined = 1
    next
  }
  logical_mask = mask_full()
  scan_logical(logical, logical_line, logical_mask)
  pending = 0
  if (!in_heredoc) {
    hd_delim = heredoc_delim(logical, logical_mask)
    if (hd_delim != "") { in_heredoc = 1; hd_strip = HD_STRIP }
  }
}
END {
  if (FATAL) exit 2
  if (pending) scan_logical(logical, logical_line, mask_full())
  if (np == 0 && ncls == 0) {
    print "Error: token list loaded no active patterns" > "/dev/stderr"
    exit 2
  }
  if (!SCOPED)
    for (h = 1; h <= nhits; h++) print hits[h]
}
