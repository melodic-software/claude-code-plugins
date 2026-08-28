#!/usr/bin/env bash
# Fail when a test suite that BUILDS a git fixture can have that fixture's
# identity land in the caller's repository.
#
#   scripts/check-fixture-git-isolation.sh            report violations, exit 1 if any
#   scripts/check-fixture-git-isolation.sh --check    same (explicit form, matches sibling gates)
#   scripts/check-fixture-git-isolation.sh --list     list every fixture-building suite and its verdict
#
# Exit: 0 clean, 1 a violation or a stale baseline entry, 2 usage.
#
# WHY (#2840). The repo's fixture idiom is `git -C "$fixture" ...`. It is a good
# readability and copy-paste guard. It is NOT an isolation guarantee: `-C` only
# changes directory, while an exported ABSOLUTE GIT_DIR overrides repository
# DISCOVERY outright, and `git config` writes its default --local scope to
# whatever gitdir finally resolves to. So a suite that inherited such an
# environment writes its throwaway fixture identity into the CALLER's
# .git/config, and leaves the fixture with no .git at all. Both the
# `cd`-scoped-subshell form and the `git -C` form leak this way; only clearing
# the inherited environment isolates.
#
# What EXPORTED it is not part of the mechanism. The GIT_DIR behind the real
# incident came from an ad-hoc tool invocation; this repository has no git hook
# at any scope and core.hooksPath is unset everywhere, so "git hands GIT_DIR to
# every hook" is not what fired here and a narrower harden-the-hooks fix would
# not have caught it. The invariant this gate enforces is that a fixture never
# inherits ambient git environment, however that environment got exported.
#
# The blast radius is why this is a gate and not a lint. Worktrees share the
# main clone's .git/config, so one leak poisons every worktree of the repo at
# once. A poisoned user.email silently re-authors commits to the fixture
# identity; such a commit then fails this repo's required_signatures rule with
# `no_user` and cannot be force-pushed over, so the branch has to be abandoned
# and the tree rebuilt.
#
# WHAT COUNTS AS ISOLATED. A shell suite passes if it clears the inherited git
# environment itself:
#
#     unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
#
# GIT_CONFIG belongs in every clear list and the CREDIT signal requires it: it
# is a SECOND leak path, not another spelling of the first, because it replaces
# the file the `git config` subcommand reads and writes rather than redirecting
# discovery, so it survives `-C` and a cleared GIT_DIR alike. Official docs
# (git-config ENVIRONMENT): if no `--file` is given, `GIT_CONFIG` is used as
# if it were `--file`. That is why a suite that only unsets the discovery
# pair is still exposed.
#
# or if it sources a harness that does — scripts/test-git-helpers.sh is the
# repo's shared one. Sourced harnesses are resolved by BASENAME against the
# tracked tree and re-checked, so the set of isolating harnesses is derived on
# every run rather than hardcoded here: a new harness that clears the
# environment counts the moment it exists, and one that stops clearing it stops
# counting for every suite that sources it.
#
# PYTHON SUITES ARE IN SCOPE, and are the reason this gate is not a class inside
# scripts/check-shell-portability.sh: that gate is scoped to *.sh, and the file
# that actually caused the #2827 incident is
# plugins/disk-hygiene/skills/clean/scripts/test_hygiene.py. A gate that cannot
# see the file that fired is not a gate. A Python suite passes if it clears the
# variables from os.environ, e.g.
#
#     for _leaked_git_var in ("GIT_DIR", "GIT_WORK_TREE", ...):
#         os.environ.pop(_leaked_git_var, None)
#
# Because that idiom spans lines, the Python check is FILE-scoped rather than
# line-scoped: the file must perform an environ pop/delete AND name every
# load-bearing variable (GIT_DIR, GIT_WORK_TREE, GIT_CONFIG). A module-level
# name bound to a literal of those names, then iterated into the pop, is the
# same clear — the loop-variable tie follows that binding, not only an
# in-header literal. Python has no `source` equivalent here, so a Python
# suite must carry its own clear; there is no harness-inheritance path to
# resolve, and that is recorded as a deliberate limit rather than an oversight.
#
# DIRECTION. Over-selection is safe, under-selection is not — a suite wrongly
# required to isolate costs one line, while a suite that should have isolated
# and did not is the incident this gate exists to stop. Fixture detection is
# therefore generous.
#
# HEREDOC BODIES ARE DATA, AND THE ASYMMETRY IS THE POINT. A heredoc body is text
# the shell hands to a command; those lines never execute in the enclosing suite.
# So a token inside one cannot be evidence that this suite did anything. This
# corpus writes fixture suites through heredocs — this gate's own self-test writes
# suites containing `unset GIT_DIR …` and even a `fixture-isolation-scope:`
# declaration line as TEST DATA — so reading a heredoc body as executed code lets
# the gate hand out isolation credit that is not in effect.
#
# The two directions are therefore treated differently, and deliberately so:
#
#   CREDIT  (CLEARS, SCOPE, SOURCE) — SKIPPED inside a heredoc body. Every one of
#           the three EXCUSES a suite, and crediting a suite for data it merely
#           printed is exactly the under-selection this gate calls unsafe. SOURCE
#           counts here because sourcing an isolating harness grants credit just
#           as directly as clearing; and because CLEARS registers a file's
#           BASENAME as an isolating harness, a heredoc-only clear would make
#           the enclosing file excuse every OTHER file that sources it.
#   FIXTURE — still READ inside a heredoc body. Conscripting a suite into scope
#           over text it only wrote costs that suite one `unset` line, which is
#           the safe direction. A file that prints fixture-building commands is
#           usually a file that also runs them.
#
# Extent is tracked, not merely `<<` presence: every delimiter a code line opens
# is queued (bash allows several per line), `<<-` tab-stripping and quoted or
# backslash-escaped delimiters are honoured, `<<<` here-strings are not heredocs,
# and a terminator must match the delimiter EXACTLY. Matching loosely would end a
# body early and restore credit inside it — under-selection again — so where the
# two directions conflict the extent runs long.
#
# DECLARED SCOPE. A suite whose SUBJECT is this very mechanism cannot clear the
# environment — it has to export GIT_DIR to prove the harness survives it. Such
# a file opts out with a dedicated comment line whose content, after the `#` and
# optional whitespace, STARTS with the literal token `fixture-isolation-scope:`
# followed by a reason. Requiring line-start (rather than merely mentioning the
# string somewhere) is deliberate, and mirrors the `portability-scope:`
# declaration in scripts/check-shell-portability.sh: a doc sentence explaining
# the mechanism, or a string literal inside a detector, must not silently exempt
# a whole file for a reason it never actually declared. This escape is for a
# file that IS this gate's counter-fixture, NOT for excusing a real suite.
#
# BASELINE. scripts/fixture-git-isolation-baseline.txt grandfathers the suites
# that predate this gate, so shipping it does not red-line the corpus. Entries
# are exact paths and the gate FAILS on a stale one, so a line cannot outlive
# the debt it records. A declared scope is NOT a baseline entry: the baseline
# records debt to be drained, the declaration records a permanent property of
# the file.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

BASELINE="scripts/fixture-git-isolation-baseline.txt"
mode="check"
case "${1:-}" in
  "" | --check) ;;
  --list) mode="list" ;;
  *)
    echo "usage: scripts/check-fixture-git-isolation.sh [--check|--list]" >&2
    exit 2
    ;;
esac

# Git Bash pays ~140ms per process spawn and this corpus is ~550 shell files, so
# every classification below is ONE bulk awk pass over the whole tracked set
# rather than a grep per file. Three passes total, not eleven hundred.
#
# CLEARS: a shell file that unsets every load-bearing variable (GIT_DIR,
#   GIT_WORK_TREE, GIT_CONFIG) on one logical line via `unset` (process-wide),
#   or that wraps EVERY fixture command with `env -u`/`--unset` naming each
#   (per-command; one wrap does not isolate a later unwrapped write), or a
#   Python file that pops/deletes them from os.environ and names all three.
#   The Python arm is FILE-scoped because the idiom spans lines (a tuple of
#   names iterated into os.environ.pop), so its verdict is emitted at
#   end-of-file. The shell arm joins physical lines while the previous line
#   ends in an unescaped backslash, so a continued `git … \` / `unset … \`
#   is one unit (the same recall the Python arm already had for
#   formatter-wrapped argv).
# FIXTURE: a suite that runs a repository-creating or identity-writing git
#   command. Comments are stripped first, so prose about `git init` in a header
#   does not conscript a suite that never touches a fixture. The command form is
#   matched generously (`git init`, `git -C <dir> init`, and wrapper functions
#   like `git_quiet init`) because under-selection is the unsafe direction. The
#   Python arm must additionally match the LIST-ARGUMENT spelling
#   (`["git", "init", ...]`, `["git", "-C", str(d), "config", "user.email", …]`)
#   and the positional-passthrough wrapper (`git("-C", str(d), "config", …)`),
#   which are the three shapes this corpus actually uses.
# SOURCE: the basename of each file this one sources, so a harness can be
#   resolved without guessing how the caller spelled its path. Shell only —
#   Python suites carry their own clear (see the header).
scan() {
  awk '
    BEGIN {
      # A single quote cannot be written literally inside this single-quoted
      # awk program, so the quote CLASS is built once here and every pattern
      # needing it is a DYNAMIC regex over this string.
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
    }

    function ncount(s, re,   t) { t = s; return gsub(re, "", t) }

    # Queue every heredoc a code line opens. Bash reads bodies in the order the
    # redirections appear (`cmd <<A <<B` consumes the A body, then the B body),
    # so this is a FIFO and not a single pending delimiter. A literal apostrophe
    # cannot appear anywhere in this awk program, comments included — it would
    # close the shell quoting the whole program sits inside.
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
      # The operator line itself IS code; its body starts on the next line.
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
    function ident_write(s,   t) {
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
      return s ~ ("(environ[ \t]*\\.[ \t]*pop|delenv)[ \t]*\\([ \t]*" Q name Q) ||
             s ~ ("del[ \t]+os[ \t]*\\.[ \t]*environ[ \t]*\\[[ \t]*" Q name Q)
    }

    # The other spelling this corpus uses is a loop: the iterable literal binds
    # the names and the body performs the pop. The two halves are tied through
    # the LOOP VARIABLE, so a pop and a mention that never met cannot credit
    # each other.
    function pops_var(s, v) {
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
      }
      for (i = 1; i <= NREQ; i++)
        if (pops_literal(s, REQ[i])) CLEARED[REQ[i]] = 1
      for (v in LOOPVAR)
        if (pops_var(s, v))
          for (i = 1; i <= NREQ; i++)
            if (BOUND[v, REQ[i]]) CLEARED[REQ[i]] = 1
    }

    function py_drain() {
      if (pending != "") { py_logical(pending); pending = ""; depth = 0; joined = 0 }
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
          sub(/.*\//, "", path)
          if (path != "") print "SOURCE\t" FILENAME "\t" path
        }
      }
    }

    function sh_drain() {
      if (sh_pending != "") { sh_logical(sh_pending); sh_pending = ""; sh_joined = 0 }
    }

    function sh_flush() {
      sh_drain()
      if (cur != "" && (SH_UNSET || (SH_ENV && !SH_ENV_GAP))) print "CLEARS\t" cur
    }

    FILENAME != cur {
      py_drain(); flush_py(); sh_flush()
      cur = FILENAME
      split("", CLEARED); split("", BOUND); split("", LOOPVAR); split("", CONST)
      pending = ""; depth = 0; joined = 0
      sh_pending = ""; sh_joined = 0
      SH_UNSET = 0; SH_ENV = 0; SH_ENV_GAP = 0
      split("", HD_DELIM); split("", HD_STRIP)
      HD_N = 0; HD_HEAD = 1; HD_ACTIVE = 0; hd_line = 0; SH_DATA_ONLY = 0
      ispy = (FILENAME ~ /\.py$/)
    }
    {
      line = $0; gsub(/\r/, "", line); code = line; sub(/#.*/, "", code)
      # Python has no heredocs, so the state machine runs for shell only and
      # hd_line stays 0 there. (A triple-quoted Python string is the analogous
      # data region; the Python arm credits only os.environ pops, so that is
      # tracked separately if it ever proves reachable.)
      hd_line = 0
      if (!ispy) hd_step(line, code)
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
      sh_pending = (sh_pending == "" ? piece : sh_pending " " piece)
      sh_joined++
      if (!cont || sh_joined >= MAXJOIN) sh_drain()
    }
    END { py_drain(); flush_py(); sh_flush() }
  ' "$@"
}

declare -A ISOLATING_BASENAME=() IS_FIXTURE=() CLEARS_FILE=() SCOPED=()
declare -A SOURCES=()

mapfile -t tracked < <(git ls-files '*.sh' '*.py' 2>/dev/null)
((${#tracked[@]} > 0)) || {
  echo "error: no tracked *.sh or *.py files found — run from inside the repository" >&2
  exit 2
}

while IFS=$'\t' read -r kind file extra; do
  case "$kind" in
    CLEARS)
      ISOLATING_BASENAME["${file##*/}"]=1
      CLEARS_FILE["$file"]=1
      ;;
    FIXTURE) IS_FIXTURE["$file"]=1 ;;
    SCOPE) SCOPED["$file"]=1 ;;
    SOURCE) SOURCES["$file"]="${SOURCES["$file"]:-} $extra" ;;
    *) ;;
  esac
done < <(scan "${tracked[@]}")

sources_isolating_harness() {
  local b
  for b in ${SOURCES["$1"]:-}; do
    [[ -n "${ISOLATING_BASENAME[$b]:-}" ]] && return 0
  done
  return 1
}

clears_env() { [[ -n "${CLEARS_FILE["$1"]:-}" ]]; }

declared_scope() { [[ -n "${SCOPED["$1"]:-}" ]]; }

declare -A BASELINED=()
if [[ -f "$BASELINE" ]]; then
  # One sed pass, not one command substitution per line: on Git Bash a spawn per
  # line turns a 70-line file into minutes of wall clock.
  while IFS= read -r line; do
    [[ -n "$line" ]] && BASELINED["$line"]=1
  done < <(sed 's/\r$//; s/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d' "$BASELINE")
fi

violations=()
covered=()
declare -A STILL_VIOLATING=()

# The suite set spans both languages. Python test files are named `test_*.py`
# or `*_test.py` in this corpus; both spellings are enumerated so a rename
# between them cannot drop a suite out of scope.
mapfile -t suites < <(git ls-files '*.test.sh' '*test_*.py' '*_test.py' 2>/dev/null | sort -u)
for t in "${suites[@]}"; do
  [[ -n "${IS_FIXTURE[$t]:-}" ]] || continue
  # Actually clearing outranks declaring. A file that clears is reported as
  # `isolated` even if it also carries the token, which matters because a file
  # holding the token as TEST DATA — this gate's own self-test writes fixture
  # suites containing a declaration line — would otherwise be reported as
  # merely declared and its real property hidden. Ordering this way keeps the
  # accidental-token surface to files that genuinely do not clear.
  if clears_env "$t" || sources_isolating_harness "$t"; then
    covered+=("$t")
    [[ "$mode" == "list" ]] && printf 'isolated    %s\n' "$t"
    continue
  fi
  if declared_scope "$t"; then
    covered+=("$t")
    [[ "$mode" == "list" ]] && printf 'declared    %s\n' "$t"
    continue
  fi
  STILL_VIOLATING["$t"]=1
  if [[ -n "${BASELINED[$t]:-}" ]]; then
    [[ "$mode" == "list" ]] && printf 'baselined   %s\n' "$t"
    continue
  fi
  violations+=("$t")
  [[ "$mode" == "list" ]] && printf 'VIOLATION   %s\n' "$t"
done

stale=()
for b in "${!BASELINED[@]}"; do
  [[ -n "${STILL_VIOLATING[$b]:-}" ]] || stale+=("$b")
done

if [[ "$mode" == "list" ]]; then
  printf '\n%d isolated, %d baselined, %d violating\n' \
    "${#covered[@]}" "$((${#BASELINED[@]} - ${#stale[@]}))" "${#violations[@]}"
  exit 0
fi

rc=0

if ((${#violations[@]} > 0)); then
  rc=1
  echo "FIXTURE GIT ISOLATION: ${#violations[@]} suite(s) build a git fixture without clearing the inherited git environment." >&2
  echo >&2
  for v in "${violations[@]}"; do echo "  $v" >&2; done
  echo >&2
  echo "Each builds a repository or writes a git identity, so under an inherited ABSOLUTE" >&2
  echo "GIT_DIR — which overrides repository discovery and outranks -C — it writes that" >&2
  echo "identity into the CALLER's .git/config, shared by every worktree of the clone," >&2
  echo "instead of into its fixture. Any process can export it; a git hook is one way and" >&2
  echo "an ad-hoc command is another, which is why this is cleared unconditionally." >&2
  echo >&2
  echo "Fix by clearing the environment once, at the top of the suite:" >&2
  echo >&2
  echo "    unset GIT_DIR GIT_WORK_TREE GIT_CONFIG" >&2
  echo >&2
  echo "or by sourcing a harness that already does (scripts/test-git-helpers.sh)." >&2
  echo "Do NOT add a new suite to $BASELINE — it records pre-existing debt only." >&2
fi

if ((${#stale[@]} > 0)); then
  rc=1
  echo >&2
  echo "STALE BASELINE: ${#stale[@]} entry(ies) in $BASELINE no longer shadow a violation." >&2
  echo "Delete each line below — the debt it recorded is paid." >&2
  echo >&2
  while IFS= read -r s; do echo "  $s" >&2; done < <(printf '%s\n' "${stale[@]}" | sort)
fi

if ((rc == 0)); then
  printf 'fixture git isolation: OK (%d isolated, %d baselined)\n' "${#covered[@]}" "${#BASELINED[@]}"
fi
exit "$rc"
