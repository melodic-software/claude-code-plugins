#!/usr/bin/env bash
# Fail when a test suite that BUILDS a git fixture can have that fixture's
# identity land in the caller's repository, or when a suite that RUNS git can
# read the host's global or system git config (SECOND RULE below).
#
#   scripts/check-fixture-git-isolation.sh            report violations, exit 1 if any
#   scripts/check-fixture-git-isolation.sh --check    same (explicit form, matches sibling gates)
#   scripts/check-fixture-git-isolation.sh --list     list every fixture-building suite and its verdict
#
# Exit: 0 clean, 1 a violation or a stale baseline entry, 2 usage.
#
# WHY. The repo's fixture idiom is `git -C "$fixture" ...`. It is a good
# readability and copy-paste guard. It is not an isolation guarantee: `-C` only
# changes directory, while an exported ABSOLUTE GIT_DIR overrides repository
# DISCOVERY outright, and `git config` writes its default --local scope to
# whatever gitdir finally resolves to. So a suite that inherited such an
# environment writes its throwaway fixture identity into the CALLER's
# .git/config, and leaves the fixture with no .git at all. Both the
# `cd`-scoped-subshell form and the `git -C` form leak this way; only clearing
# the inherited environment isolates.
#
# What EXPORTED it is not part of the mechanism. The invariant this gate
# enforces is that a fixture never inherits ambient git environment, however
# that environment got exported.
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
# scripts/check-shell-portability.sh: that gate is scoped to *.sh, and a Python
# suite leaks the same way. A Python suite passes if it clears the variables
# from os.environ, e.g.
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
# backslash-escaped delimiters are honored, `<<<` here-strings are not heredocs,
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
# file that is this gate's counter-fixture, not for excusing a real suite.
#
# BASELINE. scripts/fixture-git-isolation-baseline.txt grandfathers the suites
# that predate this gate, so shipping it does not red-line the corpus. Entries
# are exact paths and the gate FAILS on a stale one, so a line cannot outlive
# the debt it records. A declared scope is not a baseline entry: the baseline
# records debt to be drained, the declaration records a permanent property of
# the file.
#
# SECOND RULE: GLOBAL AND SYSTEM CONFIG. Every suite that RUNS git (shell,
# Python, and JS `*.test.{mjs,js,cjs,ts}`), fixture-building or not, must have
# GIT_CONFIG_GLOBAL exported and GIT_CONFIG_NOSYSTEM=1 (or GIT_CONFIG_SYSTEM)
# set before its first git command (git-config ENVIRONMENT,
# https://git-scm.com/docs/git-config#ENVIRONMENT). Otherwise that command reads the host's
# ~/.gitconfig and system config (signing, hooks, url rewrites, identity) and
# the suite passes or fails by machine. The test runners export both
# (scripts/lib/test-git-env.sh); a suite run directly gets only what it sets.
#
# The verdict is ORDERED, not per file: a set that comes after the first git
# command, or a later `unset` (a loop over GIT_CONFIG_* names included), fails
# the suite and names the line. Shell is read top to bottom; a sourced harness
# grants both at its `source` line when it leaves both set, resolved by path
# (suite directory, its ancestors, then the repository root) and, when the
# path cannot be resolved, only if every tracked file of that basename sets
# both. Python and JS module-level code is read in order too, but a call in an
# indented (function or test) body runs after the module loads, so it is
# judged against the end-of-file state. A git call handed an `env=` (Python)
# or `env:` (JS) dict is judged by that dict: one naming both passes, one
# that spreads the process environment inherits it, and one built fresh, or
# filtered of GIT_*, without both fails outright.
#
# Known limits: a set inside a shell function body counts at its line whether
# or not the function is ever called, and an env dict is tracked by name,
# file-wide, so two functions binding the same name share the latest binding.
# Fix a suite with a top-level export, never by relying on either.
#
# The same `fixture-isolation-scope:` declaration (`#` or `//` comment)
# exempts a suite from this rule, for a suite that must read the host config;
# scripts/fixture-git-global-baseline.txt, when present, is this rule's
# baseline, with the same exact-path and stale-entry semantics.
#
# Implementation: the awk scan emits `G` events per file, in order (S/U set
# or unset GIT_CONFIG_GLOBAL or GIT_CONFIG_NOSYSTEM, R a git command, F one in
# a function body, B one handed a dict that drops both, D one handed a named
# dict, C a sourced file, K a dict's end-of-file class). g_eval replays them
# to the first offending line; g_resolve maps a `source` token to a tracked
# file without forking; g_harness memoizes each harness's verdict.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
cd "$SCRIPT_DIR/.." || exit 1
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

BASELINE="scripts/fixture-git-isolation-baseline.txt"
GBASELINE="scripts/fixture-git-global-baseline.txt"
mode="check"
case "${1:-}" in
"" | --check) ;;
--list) mode="list" ;;
*)
  echo "usage: scripts/check-fixture-git-isolation.sh [--check|--list]" >&2
  exit 2
  ;;
esac

# Git Bash pays a high per-process spawn cost, so every classification below is
# one bulk awk pass over the whole tracked set rather than a grep per file.
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
      if (seg ~ /^[ \t]*unset[ \t]/) {
        if (seg ~ /GIT_CONFIG_GLOBAL/) g_ev("U", ln, "G")
        if (seg ~ /GIT_CONFIG_NOSYSTEM/) g_ev("U", ln, "N")
      }
    }

    # The git commands of one shell logical line. Quoted text is dropped
    # first so a `|`, `;` or the word git inside a message or a `bash -c`
    # string is not read as a command: single-quoted spans always, and
    # double-quoted spans that hold no command substitution. Heredoc bodies
    # still count (conscription is the safe direction), but only a command
    # word: a backtick in a markdown body is not command substitution.
    function sh_global_git(s, ln, data,   t, parts, np, k, m) {
      if (!index(s, "git")) return
      t = s
      gsub(/\\[$`"]/, "", t)
      while (match(t, QSPAN)) {
        m = substr(t, RSTART, RLENGTH)
        if (substr(m, 1, 1) == SQ || (m !~ /\$\(/ && m !~ /`/)) m = "_"
        else m = "\001" substr(m, 2, RLENGTH - 2) "\001"
        t = substr(t, 1, RSTART - 1) m substr(t, RSTART + RLENGTH)
      }
      # A quote left open is text the comment strip cut short (`# 9` inside
      # a string); the rest of the line is that string, not code.
      if (match(t, ("[\"" SQ "]"))) t = substr(t, 1, RSTART - 1)
      np = split(t, parts, /[ \t]*(\|\|?|&&|;)[ \t]*/)
      for (k = 1; k <= np; k++)
        if (sh_runs_git(parts[k], data) && !(parts[k] ~ /GIT_CONFIG_GLOBAL=/ && parts[k] ~ NOSYS_ON))
          g_ev("R", ln, "")
    }

    # Classify an environment-dict expression: "inherit" keeps the process
    # environment (and with it the runner exports), "fresh" builds a new one
    # (or filters GIT_* out of it), "" is not an environment expression.
    function env_rhs(r) {
      sub(/^[ \t]+/, "", r)
      if (r ~ /\*\*[ \t]*(os[ \t]*\.[ \t]*)?environ/ || r ~ /\.\.\.[ \t]*process[ \t]*\.[ \t]*env/ ||
          r ~ /^(os[ \t]*\.[ \t]*)?environ[ \t]*\.[ \t]*copy/ || r ~ /^dict[ \t]*\([ \t]*(os[ \t]*\.[ \t]*)?environ[ \t]*[,)]/)
        return "inherit"
      if (r ~ /environ|process[ \t]*\.[ \t]*env/)
        return (r ~ /GIT_/ ? "fresh" : "inherit")
      if (r ~ /^[{]/ || r ~ /^dict[ \t]*\(/) return "fresh"
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
        # A later update of a tracked env dict that names the variables.
        for (nm in ENVK)
          if (index(s, nm ".update") || index(s, nm "[") || index(s, nm ".setdefault") || index(s, nm ".GIT_CONFIG")) {
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
      # GLOBAL RULE: a loop that unsets every GIT_CONFIG_* name the
      # environment holds (`for v in $(env | sed … GIT_CONFIG_…); do unset`)
      # spans statements, so it is matched on the whole logical line.
      n = split(s, segs, /[ \t]*(\|\||&&|;)[ \t]*/)
      if (!SH_DATA_ONLY && s ~ /GIT_CONFIG_([^A-Za-z0-9_]|$)/)
        for (i = 1; i <= n; i++)
          if (segs[i] ~ /^[ \t]*(do[ \t]+)?unset[ \t]/) { g_ev("U", SH_LN, "G"); g_ev("U", SH_LN, "N"); break }
      if (!SH_DATA_ONLY) for (i = 1; i <= n; i++) sh_global_env(segs[i], SH_LN)
      sh_global_git(s, SH_LN, SH_DATA_ONLY)
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
  ' "$@"
}

declare -A ISOLATING_BASENAME=() IS_FIXTURE=() CLEARS_FILE=() SCOPED=() SOURCES=()
declare -A GEV=() BYBASE=() GHARNESS=()

mapfile -t tracked < <(git ls-files '*.sh' '*.py' 2>/dev/null)
((${#tracked[@]} > 0)) || {
  echo "error: no tracked *.sh or *.py files found — run from inside the repository" >&2
  exit 2
}
mapfile -t js_suites < <(git ls-files '*.test.mjs' '*.test.js' '*.test.cjs' '*.test.ts' 2>/dev/null)
declare -A IS_TRACKED=()
for f in "${tracked[@]}"; do
  IS_TRACKED["$f"]=1
  [[ "$f" == *.sh ]] && BYBASE["${f##*/}"]+=" $f"
done

while IFS=$'\t' read -r kind file extra; do
  case "$kind" in
  CLEARS)
    ISOLATING_BASENAME["${file##*/}"]=1
    CLEARS_FILE["$file"]=1
    ;;
  FIXTURE) IS_FIXTURE["$file"]=1 ;;
  SCOPE) SCOPED["$file"]=1 ;;
  SOURCE) SOURCES["$file"]="${SOURCES["$file"]:-} $extra" ;;
  G) GEV["$file"]+=" ${extra//$'\t'/:}" ;;
  *) ;;
  esac
done < <(scan "${tracked[@]}" ${js_suites[@]+"${js_suites[@]}"})

g_eval() {
  local ev kind rest ln arg state=0 bad="" bit late="" deferred
  local -A fin=()
  for ev in ${GEV["$1"]:-}; do
    [[ "$ev" == K:* ]] || continue
    arg="${ev#K:*:}"
    fin["${arg%%=*}"]="${arg#*=}"
  done
  for ev in ${GEV["$1"]:-}; do
    kind="${ev%%:*}" rest="${ev#*:}"
    ln="${rest%%:*}" arg="${rest#*:}"
    bit=1
    [[ "$arg" == N ]] && bit=2
    case "$kind" in
    S) state=$((state | bit)) ;;
    U) state=$((state & ~bit)) ;;
    D)
      deferred=0
      [[ "$arg" == *:F ]] && arg="${arg%:F}" deferred=1
      case "${fin[$arg]:-inherit}" in
      full) ;;
      fresh) [[ -n "$bad" ]] || bad="$ln" ;;
      *)
        if ((deferred)); then
          [[ -n "$late" ]] || late="$ln"
        else
          ((state == 3)) || [[ -n "$bad" ]] || bad="$ln"
        fi
        ;;
      esac
      ;;
    F) [[ -n "$late" ]] || late="$ln" ;;
    R) ((state == 3)) || [[ -n "$bad" ]] || bad="$ln" ;;
    B) [[ -n "$bad" ]] || bad="$ln" ;;
    C) (($2 < 4)) && g_harness "$1" "$arg" $(($2 + 1)) && state=3 ;;
    *) ;;
    esac
  done
  ((state == 3)) || [[ -n "$bad" || -z "$late" ]] || bad="$late"
  G_STATE=$state G_BAD=$bad
}

g_resolve() {
  local tail="${2##*[\})]}" dir="" base seg
  local -a segs out
  [[ "$tail" =~ ^\$[A-Za-z_][A-Za-z0-9_]* ]] && tail="${tail:${#BASH_REMATCH[0]}}"
  tail="${tail#/}"
  [[ "$1" == */* ]] && dir="${1%/*}"
  local -a bases=()
  while [[ -n "$dir" ]]; do
    bases+=("$dir")
    [[ "$dir" == */* ]] && dir="${dir%/*}" || dir=""
  done
  G_RES=""
  for base in ${bases[@]+"${bases[@]}"} ""; do
    IFS=/ read -ra segs <<<"${base:+$base/}$tail"
    out=()
    for seg in "${segs[@]}"; do
      case "$seg" in
      "" | .) ;;
      ..) ((${#out[@]})) && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$seg") ;;
      esac
    done
    G_RES=""
    for seg in ${out[@]+"${out[@]}"}; do G_RES+="${G_RES:+/}$seg"; done
    [[ -n "${IS_TRACKED[$G_RES]:-}" ]] && return
  done
  G_RES=""
}

g_harness() {
  local f key files
  g_resolve "$1" "$2"
  f="$G_RES"
  if [[ -n "$f" ]]; then key="$f" files="$f"; else key="${2##*/}" files="${BYBASE[${2##*/}]:-}"; fi
  if [[ -z "${GHARNESS[$key]:-}" ]]; then
    GHARNESS["$key"]=0
    if [[ -n "$files" ]]; then
      GHARNESS["$key"]=1
      for f in $files; do
        g_eval "$f" "$3"
        ((G_STATE == 3)) || {
          GHARNESS["$key"]=0
          break
        }
      done
    fi
  fi
  ((GHARNESS[$key] == 1))
}

sources_isolating_harness() {
  local b
  for b in ${SOURCES["$1"]:-}; do
    [[ -n "${ISOLATING_BASENAME[$b]:-}" ]] && return 0
  done
  return 1
}

declare -A BASELINED=()
BASELINE_ENTRIES=()
if [[ -f "$BASELINE" ]]; then
  # `inline`: entries are exact suite paths, never regexes, so a `#` anywhere on
  # the line opens the reason comment (scripts/lib/read-list.sh owns the two
  # comment families and why they must stay distinct). The shared reader is
  # pure-bash, so it spawns nothing at all -- on Git Bash a spawn per line turns
  # a 70-line file into minutes of wall clock.
  read_list::into BASELINE_ENTRIES "$BASELINE" --comments inline || exit 2
  for line in ${BASELINE_ENTRIES[@]+"${BASELINE_ENTRIES[@]}"}; do
    BASELINED["$line"]=1
  done
fi

violations=()
covered=()

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
  if [[ -n "${CLEARS_FILE[$t]:-}" ]] || sources_isolating_harness "$t"; then
    covered+=("$t")
    [[ "$mode" == "list" ]] && printf 'isolated    %s\n' "$t"
    continue
  fi
  if [[ -n "${SCOPED[$t]:-}" ]]; then
    covered+=("$t")
    [[ "$mode" == "list" ]] && printf 'declared    %s\n' "$t"
    continue
  fi
  # A baseline entry shadowing a live violation has not outlived its debt.
  # scripts/lib/read-list.sh owns the consumed-set and the diagnostic.
  read_list::mark_used "$t"
  if [[ -n "${BASELINED[$t]:-}" ]]; then
    [[ "$mode" == "list" ]] && printf 'baselined   %s\n' "$t"
    continue
  fi
  violations+=("$t")
  [[ "$mode" == "list" ]] && printf 'VIOLATION   %s\n' "$t"
done

stale=()
read_list::stale_to stale BASELINE_ENTRIES

declare -A GBASELINED=()
GBASELINE_ENTRIES=()
if [[ -f "$GBASELINE" ]]; then
  read_list::into GBASELINE_ENTRIES "$GBASELINE" --comments inline || exit 2
  for line in ${GBASELINE_ENTRIES[@]+"${GBASELINE_ENTRIES[@]}"}; do
    GBASELINED["$line"]=1
  done
fi
read_list::reset_used
gviolations=()
gchecked=0
for t in "${suites[@]}" ${js_suites[@]+"${js_suites[@]}"}; do
  [[ -n "${GEV[$t]:-}" && -z "${SCOPED[$t]:-}" ]] || continue
  g_eval "$t" 0
  [[ -z "$G_BAD" && " ${GEV[$t]}" == *" "[RFBD]:* ]] && gchecked=$((gchecked + 1))
  [[ -n "$G_BAD" ]] || continue
  read_list::mark_used "$t"
  if [[ -n "${GBASELINED[$t]:-}" ]]; then
    [[ "$mode" == "list" ]] && printf 'baselined   %s (global config)\n' "$t"
    continue
  fi
  gviolations+=("$t:$G_BAD")
  [[ "$mode" == "list" ]] && printf 'VIOLATION   %s:%s (global config)\n' "$t" "$G_BAD"
done
gstale=()
read_list::stale_to gstale GBASELINE_ENTRIES

if [[ "$mode" == "list" ]]; then
  printf '\n%d isolated, %d baselined, %d violating\n' \
    "${#covered[@]}" "$((${#BASELINED[@]} - ${#stale[@]}))" "${#violations[@]}"
  printf 'global config: %d baselined, %d violating\n' \
    "$((${#GBASELINED[@]} - ${#gstale[@]}))" "${#gviolations[@]}"
  exit 0
fi

rc=0

if ((${#gviolations[@]} > 0)); then
  rc=1
  {
    printf 'GIT GLOBAL CONFIG ISOLATION: %d suite(s) run git while reading the host global or system git config.\n\n' "${#gviolations[@]}"
    printf '  %s\n' "${gviolations[@]}"
    cat <<EOF

Each names the line of the first git command that runs with GIT_CONFIG_GLOBAL
not exported or GIT_CONFIG_NOSYSTEM=1 not set: never set, set only after that
line, unset again before it, or replaced by an env= dict that drops both. Such
a command reads the host's ~/.gitconfig and system config (signing, hooks,
url rewrites, identity), so the suite passes or fails by machine. The test
runners export both (scripts/lib/test-git-env.sh); a suite run directly does not.

Fix by exporting both before the first git command, at the top of the suite:

    export GIT_CONFIG_GLOBAL="\${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

(Python: os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull) and
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"; JS: process.env.GIT_CONFIG_GLOBAL ??=
"/dev/null" and process.env.GIT_CONFIG_NOSYSTEM = "1"), or by sourcing a
harness that does (scripts/test-git-helpers.sh), and keep both in any env dict.
A suite that must read the host config declares "# fixture-isolation-scope: <reason>".
Do not add a new suite to $GBASELINE.
EOF
  } >&2
fi

if ((${#gstale[@]} > 0)); then
  rc=1
  while IFS= read -r s; do
    read_list::stale_line "$GBASELINE" "$s" 'no longer shadows a violation'
  done < <(printf '%s\n' "${gstale[@]}" | sort)
fi

if ((${#violations[@]} > 0)); then
  rc=1
  {
    printf 'FIXTURE GIT ISOLATION: %d suite(s) build a git fixture without clearing the inherited git environment.\n\n' "${#violations[@]}"
    printf '  %s\n' "${violations[@]}"
    cat <<EOF

Each builds a repository or writes a git identity, so under an inherited ABSOLUTE
GIT_DIR — which overrides repository discovery and outranks -C — it writes that
identity into the CALLER's .git/config, shared by every worktree of the clone,
instead of into its fixture. Any process can export it; a git hook is one way and
an ad-hoc command is another, which is why this is cleared unconditionally.

Fix by clearing the environment once, at the top of the suite:

    unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

or by sourcing a harness that already does (scripts/test-git-helpers.sh).
Do not add a new suite to $BASELINE — it records pre-existing debt only.
EOF
  } >&2
fi

if ((${#stale[@]} > 0)); then
  rc=1
  printf '\n%d entry(ies) in %s no longer shadow a violation.\nDelete each line below — the debt it recorded is paid.\n\n' "${#stale[@]}" "$BASELINE" >&2
  # scripts/lib/read-list.sh owns the one STALE BASELINE diagnostic every list
  # gate here prints.
  while IFS= read -r s; do
    read_list::stale_line "$BASELINE" "$s" 'no longer shadows a violation'
  done < <(printf '%s\n' "${stale[@]}" | sort)
fi

if ((rc == 0)); then
  printf 'fixture git isolation: OK (%d isolated, %d baselined; %d git-running suites read no host config, %d baselined)\n' \
    "${#covered[@]}" "${#BASELINED[@]}" "$gchecked" "${#GBASELINED[@]}"
fi
exit "$rc"
