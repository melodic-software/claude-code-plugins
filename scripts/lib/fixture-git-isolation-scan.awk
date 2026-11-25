BEGIN {
  # The quote CLASS is built once here and every pattern needing it is a
  # DYNAMIC regex over this string, so no pattern holds a literal apostrophe.
  SQ = sprintf("%c", 39)
  Q  = "[\"" SQ "]"
  QC = "[\"" SQ ",]"
  OPEN  = "[[({]"
  CLOSE = "[]})]"
  # The variables a clear must name to earn credit, shared by both arms so
  # the two languages cannot drift apart. GIT_CONFIG is the third because
  # it is a distinct leak path (git-config ENVIRONMENT: used as --file).
  NREQ = 3; REQ[1] = "GIT_DIR"; REQ[2] = "GIT_WORK_TREE"; REQ[3] = "GIT_CONFIG"
  # A joined Python logical line is capped. An unbalanced bracket inside a
  # string literal would otherwise accumulate to end of file, and a runaway
  # join is unsafe for CLEARS specifically: it could sweep an unrelated
  # `for … in (…)` header together with an unrelated pop and re-create the
  # tie-less misclassification the tie below exists to prevent.
  MAXJOIN = 40
  # A heredoc redirection: `<<WORD`, `<<-WORD`, and the quoted or
  # backslash-escaped delimiter spellings. A here-STRING (`<<<`) is not a
  # heredoc and is neutralized before this ever runs. The delimiter must
  # look like a word, which is also what keeps an arithmetic left shift
  # (`$((n << 8))`) from opening a body that would swallow the rest of the
  # file.
  HDRE = "<<-?[ \t]*(\\\\?[A-Za-z_][A-Za-z0-9_]*|" SQ "[^" SQ "]*" SQ "|\"[^\"]*\")"
  # A complete quoted span. `<<` inside one is TEXT, not a redirection, so
  # the scan below steps over spans instead of matching into them.
  QSPAN = "\"[^\"]*\"|" SQ "[^" SQ "]*" SQ
  HD_HEAD = 1
  # GLOBAL RULE patterns. QB adds the JS template-literal quote. ASSIGN
  # is one leading `NAME=value` word of a shell command.
  QB = "[\"" SQ "`]"
  ASSIGN = "^[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|" SQ "[^" SQ "]*" SQ "|[^ \t]*)[ \t]+"
  NOSYS_ON = "(GIT_CONFIG_NOSYSTEM" QB "?[ \t]*[=:][ \t]*" QB "?(1|true|yes)|GIT_CONFIG_SYSTEM" QB "?[ \t]*[=:])"
}

# ---- GLOBAL RULE --------------------------------------------------------
# Events, in file order, for the second rule (see the header): S/U set or
# unset GIT_CONFIG_GLOBAL (G) or GIT_CONFIG_NOSYSTEM (N), R a git command
# run under the inherited environment, B a git command handed an env dict
# that drops both, C a sourced file. Consecutive R events collapse: bash
# only needs the first git command after each state change.
function g_ev(kind, ln, arg) {
  if (PJ_BODY && (kind == "S" || kind == "U")) kind = tolower(kind)
  if ((kind == "R" || kind == "F") && G_LAST == kind) return
  G_LAST = kind
  print "G\t" cur "\t" kind "\t" ln "\t" arg
}

# A shell statement whose command word is git, after stripping grouping,
# keywords, NAME=value prefixes and an `env` wrapper; or a command
# substitution that starts with git.
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

# One shell statement: its sets and unsets, skipped in a heredoc body (data).
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

# The sets, unsets and git commands of one shell logical line, in
# statement order. Quoted text is neutralized first so a `|`, `;` or the
# word git inside a message or a `bash -c` string is not read as a
# command: a single-quoted span is dropped, a double-quoted span with no
# command substitution keeps its text with its separators blanked (so
# `GIT_CONFIG_NOSYSTEM="1"` still reads as a set), and one with a command
# substitution is kept. `loop` marks a line holding an unset loop over
# GIT_CONFIG_* names, whose name pattern sits in the dropped quotes.
# Heredoc bodies still count for git (conscription is the safe
# direction), but only a command word, and never for sets or unsets.
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
  # A quote left open is text the comment strip cut short (`# 9` inside
  # a string); the rest of the line is that string, not code.
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

# Classify an environment-dict expression: "inherit" keeps the process
# environment (and with it the runner exports), "fresh" builds a new one
# (or filters GIT_* out of it), "" is not an environment expression.
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

# The env a git call is handed: "none", "full" (names both variables),
# "inherit", "fresh", or "defer:NAME" for a name bound later in the file
# (a helper defined above the dict it uses), resolved against the final
# binding at end of file.
function call_env(s, js,   v, nm, cls, t, c, best) {
  if (js) { if (!match(s, /[{,][ \t]*env[ \t]*(:|[,}])/)) return "none"
    if (substr(s, RSTART + RLENGTH - 1, 1) != ":") { s = "env"; RSTART = 1; RLENGTH = 0 } }
  else if (!match(s, /[(,][ \t]*env[ \t]*=[^=]/)) return "none"
  v = substr(s, RSTART + RLENGTH - (js ? 0 : 1))
  sub(/^[ \t]+/, "", v)
  if (v ~ /^[{]/ || v ~ /^dict[ \t]*\(/) {
    if (index(v, "GIT_CONFIG_GLOBAL") && v ~ NOSYS_ON) return "full"
    # A spread of a bound dict carries that dict: `{ ...baseEnv, x }`.
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

# End of file: the final env-dict bindings, for the deferred lookups.
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

# One Python or JS logical line, in that order: process-environment sets
# and unsets, env-dict bindings, then any git call.
function pj_global(s, ln, js,   nm, rhs, cls, v, i, t) {
  PJ_BODY = (s ~ /^[ \t]/)
  # The process environment updated from a bound dict that names both:
  # `Object.assign(process.env, gitEnv)`, `os.environ.update(GIT_ENV)`.
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
    # A later update of a tracked env dict that names the variables: a
    # removal (`del ENV[...]`, `ENV.pop(...)`, `delete env.X`) clears the
    # name it removes, any other write sets it.
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
  # An assignment to a name binds (or drops) its env-dict class.
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
      # A spread of a bound dict that names both carries them.
      t = rhs
      while (match(t, /(\.\.\.|\*\*)[ \t]*[A-Za-z_][A-Za-z0-9_.]*/)) {
        v = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
        sub(/^(\.\.\.|\*\*)[ \t]*/, "", v)
        if (v != nm && env_class(v) == "full") { ENVG[nm] = 1; ENVN[nm] = 1 }
      }
    } else delete ENVK[nm]
  }
  # An indented call sits in a function or test body, which runs after
  # the whole module has loaded: it is judged (F) against the state at
  # end of file, not at its line. Module-level code is judged in order.
  if (js ? js_runs_git(s) : py_runs_git(s)) {
    cls = call_env(s, js)
    if (cls == "fresh") { G_LAST = "B"; print "G\t" cur "\tB\t" ln "\t" }
    else if (cls ~ /^defer:/) { G_LAST = "D"; print "G\t" cur "\tD\t" ln "\t" substr(cls, 7) (s ~ /^[ \t]/ ? ":F" : "") }
    else if (cls != "full") g_ev(s ~ /^[ \t]/ ? "F" : "R", ln, "")
  }
  PJ_BODY = 0
}

function ncount(s, re,   t) { t = s; return gsub(re, "", t) }

# Queue every heredoc a code line opens. Bash reads bodies in the order the
# redirections appear (`cmd <<A <<B` consumes the A body, then the B body),
# so this is a FIFO and not a single pending delimiter.
function hd_scan(s,   t, d, strip, hpos, hlen, qpos, qlen) {
  # Almost no line opens a heredoc, and the walk below costs two match()
  # calls per iteration. One cheap test keeps that off the common path —
  # this gate is run per-commit over the whole tracked corpus.
  if (s !~ /<</) return
  t = s
  # `<<<foo` is a here-string. Left in place, HDRE would match its trailing
  # `<<foo` and open a body that never terminates.
  gsub(/<<</, "\003\003\003", t)
  # Left to right, taking whichever comes first: a heredoc operator, or a
  # quoted span to step over. Scanning for HDRE alone would read the `<<` in
  # `grep -q x <<<"a <<b"` or in any message mentioning one as a
  # redirection, open a body on a delimiter that never appears again, and
  # swallow the rest of the file. The heredoc branch is tried at the SAME
  # offset first, so a quoted DELIMITER (`<<"EOF"`) still parses as one.
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

# The terminator must be the delimiter ALONE on its line — only `<<-` strips
# leading TABS (not spaces), and trailing whitespace never terminates. Being
# lenient here would end a body early and re-credit the lines after it.
function hd_is_term(raw, delim, strip,   t) {
  t = raw
  if (strip) sub(/^\t+/, "", t)
  return t == delim
}

# Advance the heredoc state one PHYSICAL line and set hd_line, which is the
# single signal the credit-granting rules below consult.
function hd_step(raw, codeline,   before) {
  if (HD_ACTIVE) {
    # Body and terminator alike: neither is code this suite executes.
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
  # The operator line itself is code; its body starts on the next line.
  if (HD_N > before) HD_ACTIVE = 1
}

# An identity WRITE: `config [opts] user.email|user.name`. Option words are
# tolerated so `git config --local user.email X` matches, but the READ
# spellings are excluded — a `config --get-all user.name` cannot poison
# anything, and flagging it would conscript suites that only INSPECT an
# identity. (A failing read is also the quiet half of this bug: it falls
# through to ~/.gitconfig and still returns 0, while the write hard-fails.)
# The read spellings are removed EXTENT BY EXTENT rather than tested against
# the whole line. A line-wide `!~ /--get/` test would let one read suppress a
# real write sharing the line (`git -C d config user.email x && git config
# --get user.name`) — an under-selection, the direction this gate calls
# unsafe. Deleting each read occurrence first leaves any write on the line
# still visible.
# Each early index() return below lists substrings; every pattern in that function,
# callees included, requires at least one of them. A new pattern must too.
function ident_write(s,   t) {
  if (!index(s, "user.")) return 0
  t = s
  gsub(/config[ \t]+(--[a-zA-Z-]+[ \t]+)*--(get|get-all|get-regexp|get-urlmatch|list)([ \t]+--[a-zA-Z-]+)*[ \t]+user\.(email|name)/, " ", t)
  return t ~ /config[ \t]+(--[a-zA-Z-]+[ \t]+)*user\.(email|name)([ \t]|$)/
}
# Fixture intent, in either language, over one already comment-stripped
# unit of code.
#
# Any run of option-and-argument pairs may sit between the command word and
# the subcommand, so `git -C <dir> init`, `git -c init.defaultBranch=main
# init` and a bare `git init` all match. Anchoring only on `-C` would miss
# `git -c … init`, which is live in this corpus — an under-selection, the
# direction this gate calls unsafe.
# Likewise the identity intent tolerates option words between `config` and
# `user.`, so `git config --local user.email X` is matched, and the
# transient `-c user.email=X` spelling counts as fixture work even though it
# cannot itself poison anything.
#
# The second half covers the Python spellings. A git argv is a list of
# quoted words, so the shell patterns (which need bare words separated by
# whitespace) never match it. Quotes and commas are normalized to spaces
# first, which turns ["git", "-C", str(d), "config", "user.email", x] into a
# shell-looking word sequence and lets one set of intents cover both
# languages.
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

# A clear credits a variable only when the CLEARING CALL ITSELF names it.
# Matching a pop anywhere and the name anywhere would let a file that pops
# some unrelated variable, while separately mentioning GIT_DIR, pass as
# isolated.
function pops_literal(s, name) {
  if (!index(s, "environ") && !index(s, "delenv")) return 0
  return s ~ ("(environ[ \t]*\\.[ \t]*pop|delenv)[ \t]*\\([ \t]*" Q name Q) ||
         s ~ ("del[ \t]+os[ \t]*\\.[ \t]*environ[ \t]*\\[[ \t]*" Q name Q)
}

# The other spelling this corpus uses is a loop: the iterable literal binds
# the names and the body performs the pop. The two halves are tied through
# the LOOP VARIABLE, so a pop and a mention that never met cannot credit
# each other.
function pops_var(s, v) {
  if (!index(s, "environ") && !index(s, "delenv")) return 0
  return s ~ ("(environ[ \t]*\\.[ \t]*pop|delenv)[ \t]*\\([ \t]*" v "[ \t]*[,)]") ||
         s ~ ("del[ \t]+os[ \t]*\\.[ \t]*environ[ \t]*\\[[ \t]*" v "[ \t]*\\]")
}

function py_logical(s,   i, v, hdr, cname) {
  if (is_fixture(s)) print "FIXTURE\t" FILENAME
  # A module-level name bound to a literal of the required names is the
  # other spelling of the in-header tuple. Credit still requires a later
  # loop over THAT name to perform the pop — a constant that merely
  # mentions the names, or a pop that never met the constant, cannot
  # satisfy the tie.
  # Any assignment to a name drops its previous CONST binding. Only a
  # list/tuple literal then re-populates it — `LEAKED = get_names()`
  # must not keep the names an earlier literal left behind.
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
    # A REBOUND loop variable starts from nothing. Without this, a second
    # `for _v in ("SOMETHING_ELSE",): os.environ.pop(_v, None)` would
    # harvest the binding an earlier, unrelated loop left behind — the same
    # untied credit the tie exists to prevent, reached by a different route.
    for (i = 1; i <= NREQ; i++) delete BOUND[v, REQ[i]]
    for (i = 1; i <= NREQ; i++)
      if (s ~ (Q REQ[i] Q)) BOUND[v, REQ[i]] = 1
    LOOPG[v] = (s ~ (Q "GIT_CONFIG_GLOBAL" Q))
    LOOPN[v] = (s ~ (Q "GIT_CONFIG_NOSYSTEM" Q))
  } else if (match(s, /for[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]+in[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    # `for _v in LEAKED:` — the iterable is a name, not a literal. Copy
    # whatever that name currently binds; a rebound constant has already
    # cleared CONST above.
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

# A shell physical line continues when the comment-stripped text, trimmed,
# ends in an unescaped backslash. `\\` at end of line is an escaped
# backslash, not a continuation; an odd trailing run is a continuation.
function is_cont(s,   t) {
  t = s
  sub(/[ \t]+$/, "", t)
  return t ~ /(^|[^\\])(\\\\)*\\$/
}

# `env -u NAME` / `env --unset NAME` / `env --unset=NAME` is a correct
# per-command clear. Credit requires the clearing call itself to name
# every required variable, matching the unset-statement rule: a later
# mention on the same line cannot grant it, and naming only the discovery
# pair is not enough.
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
  # Score fixture / env-u / unset per STATEMENT, not per physical or
  # backslash-joined line. `env -u … git init; git config user.email`
  # is two commands: the wrap applies only to the first (GNU env:
  # removals apply while it runs COMMAND). A file-wide name presence
  # test on the joined string would credit the unwrapped write.
    n = split(s, segs, /[ \t]*(\|\||&&|;)[ \t]*/)
  sh_global(s, SH_LN, SH_DATA_ONLY, s ~ /GIT_CONFIG_([^A-Za-z0-9_]|$)/ && s ~ /unset/)
  for (i = 1; i <= n; i++) {
    fixture = is_fixture(segs[i])
    if (fixture) print "FIXTURE\t" FILENAME
    # Heredoc body: FIXTURE above still counts (conscription is the safe
    # direction), but nothing below may run — every remaining signal
    # EXCUSES the suite, and this text never executed. SH_ENV_GAP is
    # skipped along with the credit it gates: a printed fixture command is
    # not an unwrapped statement, so it must not revoke a wrap the real
    # statements earned.
    if (SH_DATA_ONLY) continue
    # `unset` is process-wide, so one statement isolates every later
    # command in the file. `env -u` is per-COMMAND, so a wrap on one
    # fixture statement must not credit a later unwrapped identity
    # write. Credit env-only when every fixture statement is itself
    # an env clear.
    if (unset_clears(segs[i])) SH_UNSET = 1
    if (env_clears(segs[i])) SH_ENV = 1
    else if (fixture) SH_ENV_GAP = 1
  }
  if (SH_DATA_ONLY) return
  if (s ~ /^[ \t]*(source|\.)[ \t]+/) {
    rest = s
    sub(/^[ \t]*(source|\.)[ \t]+/, "", rest)
    # Take the first .sh-looking token rather than everything up to the
    # first space: `. "$(dirname "$0")/lib/harness.sh"` embeds a space
    # INSIDE the path expression, and truncating there loses the basename
    # entirely — an under-selection, which is the unsafe direction here.
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
  # JS comments are `//`; a `#` there is a private field, not a comment.
  if (isjs) sub(/(^|[ \t])\/\/.*/, "", code)
  else sub(/#.*/, "", code)
  # Python has no heredocs, so the state machine runs for shell only and
  # hd_line stays 0 there. (A triple-quoted Python string is the analogous
  # data region; the Python arm credits only os.environ pops, so that is
  # tracked separately if it ever proves reachable.)
  hd_line = 0
  if (!ispy && !isjs) hd_step(line, code)
}
# JS ARM: the global rule only. A line is joined with the next ones only
# when it ends inside an argument list, array or object literal (`(`,
# `[`, `,`, or `{` after `=`, `:`, `(` or `,`). A block brace (`=> {`,
# `) {`) never starts a join: test callbacks open one on almost every
# line, and joining a whole callback body would hide the assignments
# inside it from the line-start matching below.
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
# Whole-file scope declaration. Anchored at the start of the comment CONTENT
# so that prose mentioning the token, or a detector holding it as a string
# literal, cannot exempt a file that never declared anything — and skipped
# inside a heredoc body, where a declaration line is being WRITTEN as data
# rather than declared (the self-test for this gate does exactly that).
!hd_line && line ~ /^[ \t]*#[ \t]*fixture-isolation-scope:[ \t]*[^ \t]/ { print "SCOPE\t" FILENAME }

# PYTHON ARM. Matched over LOGICAL lines, not physical ones: a formatter
# wraps a call whose argument list exceeds the line length, so
# `subprocess.run(["git", "-C", str(d), "init"])` becomes several physical
# lines with `git` and `init` on none of them together. A per-line scan sees
# no fixture there at all and the suite escapes the gate entirely — not as a
# violation, but as a file the gate cannot see. Physical lines are joined
# while bracket depth is open, which is also what keeps the wrapped
# `for _v in ("GIT_DIR", …):` clear idiom recognizable.
ispy {
  if (pending == "") pstart = FNR
  pending = (pending == "" ? code : pending " " code)
  depth += ncount(code, OPEN) - ncount(code, CLOSE)
  joined++
  if (depth <= 0 || joined >= MAXJOIN) py_drain()
  next
}

# HEREDOC BODY. Read for FIXTURE, never for credit. Any real statement still
# being joined is drained first so printed text cannot be spliced onto it.
hd_line {
  sh_drain()
  SH_DATA_ONLY = 1
  SH_LN = FNR
  sh_logical(code)
  SH_DATA_ONLY = 0
  next
}

# SHELL ARM. Same logical-line join as the Python arm, but the join
# signal is a trailing unescaped backslash rather than open brackets:
# `git -C "$d" \ init` and `unset GIT_DIR \ GIT_WORK_TREE \ GIT_CONFIG`
# are each one unit. A runaway join is capped at MAXJOIN.
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
