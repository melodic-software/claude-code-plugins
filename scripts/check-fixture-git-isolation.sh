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
# GIT_CONFIG belongs in every clear list and the harnesses here all carry it: it
# is a SECOND leak path, not another spelling of the first, because it replaces
# the file the `git config` subcommand reads and writes rather than redirecting
# discovery, so it survives `-C` and a cleared GIT_DIR alike. The CREDIT signal
# below is deliberately narrower than the recommended list — GIT_DIR plus
# GIT_WORK_TREE — because widening it would retroactively re-violate every suite
# in the corpus that already clears correctly for the discovery path. Widening
# it is tracked in #2889 rather than smuggled in here.
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
# line-scoped: the file must perform an environ pop/delete AND name both
# load-bearing variables. Python has no `source` equivalent here, so a Python
# suite must carry its own clear; there is no harness-inheritance path to
# resolve, and that is recorded as a deliberate limit rather than an oversight.
#
# DIRECTION. Over-selection is safe, under-selection is not — a suite wrongly
# required to isolate costs one line, while a suite that should have isolated
# and did not is the incident this gate exists to stop. Fixture detection is
# therefore generous.
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
# CLEARS: a shell file that unsets both load-bearing variables on one line, or
#   a Python file that pops/deletes them from os.environ and names both. The
#   Python arm is FILE-scoped because the idiom spans lines (a tuple of names
#   iterated into os.environ.pop), so its verdict is emitted at end-of-file.
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
      # the two languages cannot drift apart.
      NREQ = 2; REQ[1] = "GIT_DIR"; REQ[2] = "GIT_WORK_TREE"
      # A joined Python logical line is capped. An unbalanced bracket inside a
      # string literal would otherwise accumulate to end of file, and a runaway
      # join is unsafe for CLEARS specifically: it could sweep an unrelated
      # `for … in (…)` header together with an unrelated pop and re-create the
      # tie-less misclassification the tie below exists to prevent.
      MAXJOIN = 40
    }

    function ncount(s, re,   t) { t = s; return gsub(re, "", t) }

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
    # init` and a bare `git init` all match. Anchoring only on `-C` (the
    # narrower earlier form) missed `git -c … init`, which is live in this
    # corpus — an under-selection, the direction this gate calls unsafe.
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

    function py_logical(s,   i, v) {
      if (is_fixture(s)) print "FIXTURE\t" FILENAME
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

    FILENAME != cur {
      py_drain(); flush_py()
      cur = FILENAME
      split("", CLEARED); split("", BOUND); split("", LOOPVAR)
      pending = ""; depth = 0; joined = 0
      ispy = (FILENAME ~ /\.py$/)
    }
    { line = $0; gsub(/\r/, "", line); code = line; sub(/#.*/, "", code) }
    # Whole-file scope declaration. Anchored at the start of the comment CONTENT
    # so that prose mentioning the token, or a detector holding it as a string
    # literal, cannot exempt a file that never declared anything.
    line ~ /^[ \t]*#[ \t]*fixture-isolation-scope:[ \t]*[^ \t]/ { print "SCOPE\t" FILENAME }

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

    # SHELL ARM.
    {
      if (is_fixture(code)) print "FIXTURE\t" FILENAME
      # Comments are already stripped, and the names are matched inside the
      # `unset` STATEMENT rather than anywhere on the line, so neither prose nor
      # a later command on the same line can grant the credit.
      if (code ~ /^[ \t]*unset[ \t]/) {
        u = code
        sub(/^[ \t]*unset[ \t]+/, "", u)
        sub(/;.*/, "", u)
        if (u ~ /(^|[^A-Za-z0-9_])GIT_DIR([^A-Za-z0-9_]|$)/ &&
            u ~ /(^|[^A-Za-z0-9_])GIT_WORK_TREE([^A-Za-z0-9_]|$)/)
          print "CLEARS\t" FILENAME
      }
      if (code ~ /^[ \t]*(source|\.)[ \t]+/) {
        rest = code
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
    END { py_drain(); flush_py() }
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
