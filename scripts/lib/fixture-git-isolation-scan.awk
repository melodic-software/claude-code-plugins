BEGIN {
  SQ = sprintf("%c", 39)
  Q  = "[\"" SQ "]"
  QC = "[\"" SQ ",]"
  OPEN  = "[[({]"
  CLOSE = "[]})]"
  NREQ = 3; REQ[1] = "GIT_DIR"; REQ[2] = "GIT_WORK_TREE"; REQ[3] = "GIT_CONFIG"
  MAXJOIN = 40
  HDRE = "<<-?[ \t]*(\\\\?[A-Za-z_][A-Za-z0-9_]*|" SQ "[^" SQ "]*" SQ "|\"[^\"]*\")"
  QSPAN = "\"[^\"]*\"|" SQ "[^" SQ "]*" SQ
  HD_HEAD = 1
  QB = "[\"" SQ "`]"
  ASSIGN = "^[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|" SQ "[^" SQ "]*" SQ "|[^ \t]*)[ \t]+"
  NOSYS_ON = "(GIT_CONFIG_NOSYSTEM" QB "?[ \t]*[=:][ \t]*" QB "?(1|true|yes)|GIT_CONFIG_SYSTEM" QB "?[ \t]*[=:])"
}

function g_ev(kind, ln, arg) {
  if (PJ_BODY && (kind == "S" || kind == "U")) kind = tolower(kind)
  if ((kind == "R" || kind == "F") && G_LAST == kind) return
  G_LAST = kind
  print "G\t" cur "\t" kind "\t" ln "\t" arg
}

function sh_runs_git(seg, data,   t, prev) {
  if (!index(seg, "git")) return 0
  if (!data && (seg ~ /\$\([ \t]*git([ \t)]|$)/ || seg ~ /`[ \t]*git[ \t]/)) return 1
  t = seg
  while (1) {
    prev = t
    sub(/^[ \t]+/, "", t)
    sub(/^[({!][ \t]*/, "", t)
    sub(/^(if|then|do|else|elif|while|until|time|command|exec|builtin|eval)[ \t]+/, "", t)
    sub(ASSIGN, "", t)
    sub(/^env[ \t]+((-[^ \t]+|[A-Za-z_][A-Za-z0-9_]*=[^ \t]*)[ \t]+)*/, "", t)
    if (t == prev) break
  }
  return t ~ /^git([ \t]|$)/
}

function sh_global_env(seg, ln) {
  if (!index(seg, "GIT_CONFIG_")) return
  if (seg ~ /^[ \t]*(export|(declare|typeset)[ \t]+-[A-Za-z]*x[A-Za-z]*)[ \t]/) {
    if (seg ~ /[ \t]GIT_CONFIG_GLOBAL(=|[ \t]|$)/) g_ev("S", ln, "G")
    if (seg ~ ("[ \t]" NOSYS_ON)) g_ev("S", ln, "N")
  }
  if (seg ~ /^[ \t]*(do[ \t]+|then[ \t]+)?unset[ \t]/) {
    if (seg ~ /GIT_CONFIG_GLOBAL/) g_ev("U", ln, "G")
    if (seg ~ /GIT_CONFIG_NOSYSTEM/) g_ev("U", ln, "N")
  }
}

function sh_global(s, ln, data, loop,   t, parts, np, k, m) {
  if (!index(s, "git") && !index(s, "GIT_CONFIG_")) return
  t = s
  gsub(/\\[$`"]/, "", t)
  while (match(t, QSPAN)) {
    m = substr(t, RSTART, RLENGTH)
    if (substr(m, 1, 1) == SQ) m = "_"
    else if (m !~ /\$\(/ && m !~ /`/) { gsub(/[|;&]/, "_", m); sub(/^"/, "\002", m); sub(/"$/, "\002", m) }
    else m = "\001" substr(m, 2, RLENGTH - 2) "\001"
    t = substr(t, 1, RSTART - 1) m substr(t, RSTART + RLENGTH)
  }
  if (match(t, ("[\"" SQ "]"))) t = substr(t, 1, RSTART - 1)
  gsub(/\002/, "\"", t)
  np = split(t, parts, /[ \t]*(\|\|?|&&|;)[ \t]*/)
  for (k = 1; k <= np; k++) {
    if (!data) {
      sh_global_env(parts[k], ln)
      if (loop && parts[k] ~ /^[ \t]*(do[ \t]+)?unset[ \t]/) { g_ev("U", ln, "G"); g_ev("U", ln, "N") }
    }
    if (sh_runs_git(parts[k], data) && !(parts[k] ~ /GIT_CONFIG_GLOBAL=/ && parts[k] ~ NOSYS_ON))
      g_ev("R", ln, "")
  }
}

function env_rhs(r) {
  sub(/^[ \t]+/, "", r)
  if (r ~ /\*\*[ \t]*(os[ \t]*\.[ \t]*)?environ/ || r ~ /\.\.\.[ \t]*process[ \t]*\.[ \t]*env/ ||
      r ~ /^(os[ \t]*\.[ \t]*)?environ[ \t]*\.[ \t]*copy/ || r ~ /^dict[ \t]*\([ \t]*(os[ \t]*\.[ \t]*)?environ[ \t]*[,)]/)
    return "inherit"
  if (r ~ /^[{]/ || r ~ /^dict[ \t]*\(/) {
    if (r ~ /environ[ \t]*\.[ \t]*items[ \t]*\(/ || r ~ /entries[ \t]*\([ \t]*process[ \t]*\.[ \t]*env/)
      return (r ~ /GIT_/ ? "fresh" : "inherit")
    return "fresh"
  }
  if (r ~ /environ|process[ \t]*\.[ \t]*env/)
    return (r ~ /GIT_/ ? "fresh" : "inherit")
  return ""
}

function env_class(nm) {
  if (nm ~ /^(os\.)?environ$|^process\.env$/) return "inherit"
  if (!(nm in ENVK)) return ""
  return (ENVG[nm] && ENVN[nm]) ? "full" : ENVK[nm]
}

function call_env(s, js,   v, nm, cls, t, c, best) {
  if (js) { if (!match(s, /[{,][ \t]*env[ \t]*(:|[,}])/)) return "none"
    if (substr(s, RSTART + RLENGTH - 1, 1) != ":") { s = "env"; RSTART = 1; RLENGTH = 0 } }
  else if (!match(s, /[(,][ \t]*env[ \t]*=[^=]/)) return "none"
  v = substr(s, RSTART + RLENGTH - (js ? 0 : 1))
  sub(/^[ \t]+/, "", v)
  if (v ~ /^[{]/ || v ~ /^dict[ \t]*\(/) {
    if (index(v, "GIT_CONFIG_GLOBAL") && v ~ NOSYS_ON) return "full"
    best = ""; t = v
    while (match(t, /(\.\.\.|\*\*)[ \t]*[A-Za-z_][A-Za-z0-9_.]*/)) {
      nm = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
      sub(/^(\.\.\.|\*\*)[ \t]*/, "", nm)
      c = env_class(nm)
      if (c == "full") return "full"
      if (c == "") { if (best == "") best = "defer:" nm }
      else if (c == "inherit" && best !~ /^defer/) best = "inherit"
    }
    if (best != "") return best
    cls = env_rhs(v)
    return cls == "" ? "fresh" : cls
  }
  if (match(v, /^((self|this)\.)?[A-Za-z_][A-Za-z0-9_]*/)) {
    nm = substr(v, 1, RLENGTH)
    c = env_class(nm)
    return c == "" ? "defer:" nm : c
  }
  return "inherit"
}

function g_flush(   nm) {
  if (cur == "") return
  for (nm in ENVK) print "G\t" cur "\tK\t0\t" nm "=" env_class(nm)
}

function py_runs_git(s,   t) {
  if (!index(s, "git")) return 0
  t = s
  gsub(("([A-Za-z]*(Error|Exception|Expired)|which|assert[A-Za-z]*|skipTest|startswith|endswith|get|index|count|find|split|join|print)[ \t]*\\([ \t]*" Q "git" Q), "", t)
  return t ~ ("\\[[ \t]*" Q "git" Q "[ \t]*[],]") || t ~ ("\\([ \t]*" Q "git" Q "[ \t]*,") ||
         t ~ ("(run|call|check_output|check_call|Popen|system|popen|getoutput|getstatusoutput)[ \t]*\\([ \t]*" Q "git[ \t]")
}

function js_runs_git(s) {
  if (!index(s, "git")) return 0
  return s ~ ("(execFileSync|execFile|spawnSync|spawn|execa|execaSync|execFileAsync)[ \t]*\\([ \t]*" QB "git" QB "[ \t]*[,)]") ||
         s ~ ("(execSync|exec|execAsync)[ \t]*\\([ \t]*" QB "git[ \t]")
}

function pj_global(s, ln, js,   nm, rhs, cls, v, i, t) {
  PJ_BODY = (s ~ /^[ \t]/)
  if (match(s, /(Object[ \t]*\.[ \t]*assign[ \t]*\([ \t]*process[ \t]*\.[ \t]*env|environ[ \t]*\.[ \t]*update[ \t]*\()[ \t]*,?[ \t]*[A-Za-z_][A-Za-z0-9_.]*[ \t]*\)/)) {
    nm = substr(s, RSTART, RLENGTH)
    sub(/^.*[(,][ \t]*/, "", nm); sub(/[ \t]*\)$/, "", nm)
    if (env_class(nm) == "full") { g_ev("S", ln, "G"); g_ev("S", ln, "N") }
  }
  if (index(s, "GIT_CONFIG_")) {
    if (js) {
      if (s ~ ("process[ \t]*\\.[ \t]*env[ \t]*(\\.[ \t]*GIT_CONFIG_GLOBAL|\\[[ \t]*" QB "GIT_CONFIG_GLOBAL" QB "[ \t]*\\])[ \t]*(\\?\\?|\\|\\|)?=[^=]") ||
          (s ~ /Object[ \t]*\.[ \t]*assign[ \t]*\([ \t]*process[ \t]*\.[ \t]*env/ && index(s, "GIT_CONFIG_GLOBAL"))) g_ev("S", ln, "G")
      if (s ~ ("process[ \t]*\\.[ \t]*env[ \t]*(\\.[ \t]*GIT_CONFIG_NOSYSTEM|\\[[ \t]*" QB "GIT_CONFIG_NOSYSTEM" QB "[ \t]*\\])[ \t]*(\\?\\?|\\|\\|)?=[ \t]*" QB "?(1|true|yes)") ||
          (s ~ /Object[ \t]*\.[ \t]*assign[ \t]*\([ \t]*process[ \t]*\.[ \t]*env/ && s ~ NOSYS_ON)) g_ev("S", ln, "N")
      if (s ~ /delete[ \t]+process[ \t]*\.[ \t]*env[^;]*GIT_CONFIG_GLOBAL/) g_ev("U", ln, "G")
      if (s ~ /delete[ \t]+process[ \t]*\.[ \t]*env[^;]*GIT_CONFIG_NOSYSTEM/) g_ev("U", ln, "N")
    } else {
      if (s ~ ("environ[ \t]*\\[[ \t]*" Q "GIT_CONFIG_GLOBAL" Q "[ \t]*\\][ \t]*=[^=]") ||
          s ~ ("(environ[ \t]*\\.[ \t]*setdefault|setenv|putenv)[ \t]*\\([ \t]*" Q "GIT_CONFIG_GLOBAL" Q) ||
          ((s ~ /environ[ \t]*\.[ \t]*update[ \t]*\(/ || s ~ /patch[ \t]*\.[ \t]*dict[ \t]*\([ \t]*(os[ \t]*\.[ \t]*)?environ/) && index(s, "GIT_CONFIG_GLOBAL"))) g_ev("S", ln, "G")
      if (s ~ ("environ[ \t]*\\[[ \t]*" Q "GIT_CONFIG_NOSYSTEM" Q "[ \t]*\\][ \t]*=[ \t]*" Q "?(1|true|yes)") ||
          s ~ ("(environ[ \t]*\\.[ \t]*setdefault|setenv|putenv)[ \t]*\\([ \t]*" Q "GIT_CONFIG_NOSYSTEM" Q "[ \t]*,[ \t]*" Q "?(1|true|yes)") ||
          ((s ~ /environ[ \t]*\.[ \t]*update[ \t]*\(/ || s ~ /patch[ \t]*\.[ \t]*dict[ \t]*\([ \t]*(os[ \t]*\.[ \t]*)?environ/) && s ~ NOSYS_ON)) g_ev("S", ln, "N")
      if (pops_literal(s, "GIT_CONFIG_GLOBAL")) g_ev("U", ln, "G")
      if (pops_literal(s, "GIT_CONFIG_NOSYSTEM")) g_ev("U", ln, "N")
      for (v in LOOPVAR)
        if (pops_var(s, v)) {
          if (LOOPG[v]) g_ev("U", ln, "G")
          if (LOOPN[v]) g_ev("U", ln, "N")
        }
    }
    for (nm in ENVK)
      if (s ~ /(^|[^A-Za-z0-9_])(del|delete)[ \t]/ && (index(s, nm "[") || index(s, nm ".GIT_CONFIG")) || index(s, nm ".pop")) {
        if (index(s, "GIT_CONFIG_GLOBAL")) ENVG[nm] = 0
        if (index(s, "GIT_CONFIG_NOSYSTEM")) ENVN[nm] = 0
        if (s ~ /GIT_CONFIG_(GLOBAL|NOSYSTEM)/ && ENVK[nm] == "inherit") ENVK[nm] = "fresh"
      } else if (index(s, nm ".update") || index(s, nm "[") || index(s, nm ".setdefault") || index(s, nm ".GIT_CONFIG")) {
        if (index(s, "GIT_CONFIG_GLOBAL")) ENVG[nm] = 1
        if (s ~ NOSYS_ON || s ~ ("GIT_CONFIG_NOSYSTEM" Q "?[ \t]*\\][ \t]*=[ \t]*" Q "?(1|true|yes)")) ENVN[nm] = 1
      }
  }
  if (js ? match(s, /^[ \t]*((const|let|var)[ \t]+)?((this)\.)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=[^=]/) \
         : match(s, /^[ \t]*((self)\.)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=[^=]/)) {
    nm = substr(s, RSTART, RLENGTH - 1)
    rhs = substr(s, RSTART + RLENGTH - 1)
    sub(/^[ \t]*((const|let|var)[ \t]+)?/, "", nm)
    sub(/[ \t]*=$/, "", nm)
    cls = env_rhs(rhs)
    if (cls != "") {
      ENVK[nm] = cls
      ENVG[nm] = (index(rhs, "GIT_CONFIG_GLOBAL") > 0)
      ENVN[nm] = (rhs ~ NOSYS_ON)
      t = rhs
      while (match(t, /(\.\.\.|\*\*)[ \t]*[A-Za-z_][A-Za-z0-9_.]*/)) {
        v = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
        sub(/^(\.\.\.|\*\*)[ \t]*/, "", v)
        if (v != nm && env_class(v) == "full") { ENVG[nm] = 1; ENVN[nm] = 1 }
      }
    } else delete ENVK[nm]
  }
  if (js ? js_runs_git(s) : py_runs_git(s)) {
    cls = call_env(s, js)
    if (cls == "fresh") { G_LAST = "B"; print "G\t" cur "\tB\t" ln "\t" }
    else if (cls ~ /^defer:/) { G_LAST = "D"; print "G\t" cur "\tD\t" ln "\t" substr(cls, 7) (s ~ /^[ \t]/ ? ":F" : "") }
    else if (cls != "full") g_ev(s ~ /^[ \t]/ ? "F" : "R", ln, "")
  }
  PJ_BODY = 0
}

function ncount(s, re,   t) { t = s; return gsub(re, "", t) }

function hd_scan(s,   t, d, strip, hpos, hlen, qpos, qlen) {
  if (s !~ /<</) return
  t = s
  gsub(/<<</, "\003\003\003", t)
  while (1) {
    hpos = match(t, HDRE) ? RSTART : 0
    hlen = hpos ? RLENGTH : 0
    qpos = match(t, QSPAN) ? RSTART : 0
    qlen = qpos ? RLENGTH : 0
    if (!hpos && !qpos) return
    if (!hpos || (qpos && qpos < hpos)) { t = substr(t, qpos + qlen); continue }
    d = substr(t, hpos, hlen)
    t = substr(t, hpos + hlen)
    strip = (d ~ /^<<-/)
    sub(/^<<-?[ \t]*/, "", d)
    sub(/^\\/, "", d)
    sub("^" Q, "", d)
    sub(Q "$", "", d)
    if (d != "") { HD_DELIM[++HD_N] = d; HD_STRIP[HD_N] = strip }
  }
}

function hd_is_term(raw, delim, strip,   t) {
  t = raw
  if (strip) sub(/^\t+/, "", t)
  return t == delim
}

function hd_step(raw, codeline,   before) {
  if (HD_ACTIVE) {
    hd_line = 1
    if (hd_is_term(raw, HD_DELIM[HD_HEAD], HD_STRIP[HD_HEAD])) {
      HD_HEAD++
      if (HD_HEAD > HD_N) HD_ACTIVE = 0
    }
    return
  }
  hd_line = 0
  before = HD_N
  hd_scan(codeline)
  if (HD_N > before) HD_ACTIVE = 1
}

function ident_write(s,   t) {
  if (!index(s, "user.")) return 0
  t = s
  gsub(/config[ \t]+(--[a-zA-Z-]+[ \t]+)*--(get|get-all|get-regexp|get-urlmatch|list)([ \t]+--[a-zA-Z-]+)*[ \t]+user\.(email|name)/, " ", t)
  return t ~ /config[ \t]+(--[a-zA-Z-]+[ \t]+)*user\.(email|name)([ \t]|$)/
}
function is_fixture(s,   argv) {
  if (!index(s, "git") && !index(s, "user.") && !index(s, "worktree")) return 0
  if (s ~ /git[a-zA-Z_]*[ \t]+(-[^ \t]+[ \t]+[^ \t]+[ \t]+)*(init|clone)([ \t]|$)/ ||
      s ~ /git_init[a-zA-Z_]*[ \t(]/ ||
      ident_write(s) ||
      s ~ /-c[ \t]+user\.(email|name)=/) return 1
  argv = s
  gsub(QC, " ", argv)
  if (argv ~ /(^|[^a-zA-Z_])git[ \t]*\(?[ \t]+(-[^ \t]+[ \t]+[^ \t]+[ \t]+)*(init|clone)([ \t]|$)/ ||
      ident_write(argv) ||
      argv ~ /-c[ \t]+user\.(email|name)=/ ||
      argv ~ /worktree[ \t]+add([ \t]|$)/) return 1
  return 0
}

function pops_literal(s, name) {
  if (!index(s, "environ") && !index(s, "delenv")) return 0
  return s ~ ("(environ[ \t]*\\.[ \t]*pop|delenv)[ \t]*\\([ \t]*" Q name Q) ||
         s ~ ("del[ \t]+os[ \t]*\\.[ \t]*environ[ \t]*\\[[ \t]*" Q name Q)
}

function pops_var(s, v) {
  if (!index(s, "environ") && !index(s, "delenv")) return 0
  return s ~ ("(environ[ \t]*\\.[ \t]*pop|delenv)[ \t]*\\([ \t]*" v "[ \t]*[,)]") ||
         s ~ ("del[ \t]+os[ \t]*\\.[ \t]*environ[ \t]*\\[[ \t]*" v "[ \t]*\\]")
}

function py_logical(s,   i, v, hdr, cname) {
  if (is_fixture(s)) print "FIXTURE\t" FILENAME
  if (match(s, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=/)) {
    cname = substr(s, RSTART, RLENGTH)
    sub(/^[ \t]+/, "", cname)
    sub(/[ \t]*=.*/, "", cname)
    for (i = 1; i <= NREQ; i++) delete CONST[cname, REQ[i]]
    if (s ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*[[(]/)
      for (i = 1; i <= NREQ; i++)
        if (s ~ (Q REQ[i] Q)) CONST[cname, REQ[i]] = 1
  }
  if (match(s, /for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]*[[(]/)) {
    v = substr(s, RSTART, RLENGTH)
    sub(/^for[ \t]+/, "", v)
    sub(/[ \t]+in[ \t]*[[(]$/, "", v)
    LOOPVAR[v] = 1
    for (i = 1; i <= NREQ; i++) delete BOUND[v, REQ[i]]
    for (i = 1; i <= NREQ; i++)
      if (s ~ (Q REQ[i] Q)) BOUND[v, REQ[i]] = 1
    LOOPG[v] = (s ~ (Q "GIT_CONFIG_GLOBAL" Q))
    LOOPN[v] = (s ~ (Q "GIT_CONFIG_NOSYSTEM" Q))
  } else if (match(s, /for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    hdr = substr(s, RSTART, RLENGTH)
    v = hdr
    sub(/^for[ \t]+/, "", v)
    sub(/[ \t]+in[ \t]+.*/, "", v)
    cname = hdr
    sub(/^for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+/, "", cname)
    LOOPVAR[v] = 1
    for (i = 1; i <= NREQ; i++) delete BOUND[v, REQ[i]]
    for (i = 1; i <= NREQ; i++)
      if (CONST[cname, REQ[i]]) BOUND[v, REQ[i]] = 1
    LOOPG[v] = 0; LOOPN[v] = 0
  }
  for (i = 1; i <= NREQ; i++)
    if (pops_literal(s, REQ[i])) CLEARED[REQ[i]] = 1
  for (v in LOOPVAR)
    if (pops_var(s, v))
      for (i = 1; i <= NREQ; i++)
        if (BOUND[v, REQ[i]]) CLEARED[REQ[i]] = 1
  pj_global(s, pstart, 0)
}

function py_drain() {
  if (pending != "") {
    if (isjs) pj_global(pending, pstart, 1)
    else py_logical(pending)
    pending = ""; depth = 0; joined = 0
  }
}

function flush_py(   i) {
  if (cur == "") return
  for (i = 1; i <= NREQ; i++) if (!CLEARED[REQ[i]]) return
  print "CLEARS\t" cur
}

function is_cont(s,   t) {
  t = s
  sub(/[ \t]+$/, "", t)
  return t ~ /(^|[^\\])(\\\\)*\\$/
}

function env_clears(s,   i, ok) {
  if (s !~ /(^|[ \t;|&])env[ \t]/) return 0
  for (i = 1; i <= NREQ; i++) {
    ok = (s ~ ("-u[ \t]*" REQ[i] "([^A-Za-z0-9_]|$)") ||
          s ~ ("--unset=" REQ[i] "([^A-Za-z0-9_]|$)") ||
          s ~ ("--unset[ \t]+" REQ[i] "([^A-Za-z0-9_]|$)"))
    if (!ok) return 0
  }
  return 1
}

function unset_clears(s,   u, i) {
  if (s !~ /^[ \t]*unset[ \t]/) return 0
  u = s
  sub(/^[ \t]*unset[ \t]+/, "", u)
  sub(/;.*/, "", u)
  for (i = 1; i <= NREQ; i++)
    if (u !~ ("(^|[^A-Za-z0-9_])" REQ[i] "([^A-Za-z0-9_]|$)")) return 0
  return 1
}

function sh_logical(s,   rest, path, fixture, n, i, segs) {
    n = split(s, segs, /[ \t]*(\|\||&&|;)[ \t]*/)
  sh_global(s, SH_LN, SH_DATA_ONLY, s ~ /GIT_CONFIG_([^A-Za-z0-9_]|$)/ && s ~ /unset/)
  for (i = 1; i <= n; i++) {
    fixture = is_fixture(segs[i])
    if (fixture) print "FIXTURE\t" FILENAME
    if (SH_DATA_ONLY) continue
    if (unset_clears(segs[i])) SH_UNSET = 1
    if (env_clears(segs[i])) SH_ENV = 1
    else if (fixture) SH_ENV_GAP = 1
  }
  if (SH_DATA_ONLY) return
  if (s ~ /^[ \t]*(source|\.)[ \t]+/) {
    rest = s
    sub(/^[ \t]*(source|\.)[ \t]+/, "", rest)
    if (match(rest, /[^ \t"();|&]*\.sh/)) {
      path = substr(rest, RSTART, RLENGTH)
      g_ev("C", SH_LN, path)
      sub(/.*\//, "", path)
      if (path != "") print "SOURCE\t" FILENAME "\t" path
    }
  }
}

function sh_drain() {
  if (sh_pending != "") { SH_LN = sstart; sh_logical(sh_pending); sh_pending = ""; sh_joined = 0 }
}

function sh_flush() {
  sh_drain()
  if (cur != "" && (SH_UNSET || (SH_ENV && !SH_ENV_GAP))) print "CLEARS\t" cur
}

FILENAME != cur {
  py_drain(); flush_py(); sh_flush(); g_flush()
  cur = FILENAME
  split("", CLEARED); split("", BOUND); split("", LOOPVAR); split("", CONST)
  pending = ""; depth = 0; joined = 0
  sh_pending = ""; sh_joined = 0
  SH_UNSET = 0; SH_ENV = 0; SH_ENV_GAP = 0
  split("", HD_DELIM); split("", HD_STRIP)
  HD_N = 0; HD_HEAD = 1; HD_ACTIVE = 0; hd_line = 0; SH_DATA_ONLY = 0
  G_LAST = ""; split("", ENVK); split("", ENVG); split("", ENVN); split("", LOOPG); split("", LOOPN)
  ispy = (FILENAME ~ /\.py$/)
  isjs = (FILENAME ~ /\.(mjs|cjs|js|ts)$/)
}
{
  line = $0; gsub(/\r/, "", line); code = line
  if (isjs) sub(/(^|[ \t])\/\/.*/, "", code)
  else sub(/#.*/, "", code)
  hd_line = 0
  if (!ispy && !isjs) hd_step(line, code)
}
isjs {
  if (line ~ /^[ \t]*\/\/[ \t]*fixture-isolation-scope:[ \t]*[^ \t]/) print "SCOPE\t" FILENAME
  if (pending == "" && code !~ /([[(,]|[=:(,][ \t]*\{)[ \t]*$/) { pstart = FNR; pending = code; py_drain(); next }
  if (pending == "") pstart = FNR
  pending = (pending == "" ? code : pending " " code)
  depth += ncount(code, OPEN) - ncount(code, CLOSE)
  joined++
  if (depth <= 0 || joined >= MAXJOIN) py_drain()
  next
}
!hd_line && line ~ /^[ \t]*#[ \t]*fixture-isolation-scope:[ \t]*[^ \t]/ { print "SCOPE\t" FILENAME }

ispy {
  if (pending == "") pstart = FNR
  pending = (pending == "" ? code : pending " " code)
  depth += ncount(code, OPEN) - ncount(code, CLOSE)
  joined++
  if (depth <= 0 || joined >= MAXJOIN) py_drain()
  next
}

hd_line {
  sh_drain()
  SH_DATA_ONLY = 1
  SH_LN = FNR
  sh_logical(code)
  SH_DATA_ONLY = 0
  next
}

{
  piece = code
  cont = is_cont(code)
  if (cont) sub(/[ \t]*\\[ \t]*$/, "", piece)
  if (sh_pending == "") sstart = FNR
  sh_pending = (sh_pending == "" ? piece : sh_pending " " piece)
  sh_joined++
  if (!cont || sh_joined >= MAXJOIN) sh_drain()
}
END { py_drain(); flush_py(); sh_flush(); g_flush() }
