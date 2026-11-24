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
# grants both at its `source` line when it leaves both set and runs no git of
# its own before setting them (unless it declares the scope below), resolved
# by path (suite directory, its ancestors, then the repository root) and, when
# the path cannot be resolved, only if every tracked file of that basename
# does. Statements on one line are read in order. Python and JS module-level
# code is read in order too, but a call in an indented (function or test)
# body runs after the module loads, so it is judged against the end-of-file
# state; a set inside such a body counts for those calls only, never for
# module-level code. A git call handed an `env=` (Python)
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
# dict, C a sourced file, K a dict's end-of-file class; lowercase s/u are a
# set or unset inside a function body, which only F calls see). g_eval replays them
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
  awk -f "$SCRIPT_DIR/lib/fixture-git-isolation-scan.awk" "$@"
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
  local ev kind rest ln arg state=0 fstate=0 bad="" bit late="" deferred
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
    S) state=$((state | bit)) fstate=$((fstate | bit)) ;;
    U) state=$((state & ~bit)) fstate=$((fstate & ~bit)) ;;
    s) fstate=$((fstate | bit)) ;;
    u) fstate=$((fstate & ~bit)) ;;
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
  ((fstate == 3)) || [[ -n "$bad" || -z "$late" ]] || bad="$late"
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
        ((G_STATE == 3)) && [[ -z "$G_BAD" || -n "${SCOPED[$f]:-}" ]] || {
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

mapfile -t suites < <(git ls-files '*.test.sh' '*test_*.py' '*_test.py' 2>/dev/null | sort -u)
for t in "${suites[@]}"; do
  [[ -n "${IS_FIXTURE[$t]:-}" ]] || continue
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
  while IFS= read -r s; do
    read_list::stale_line "$BASELINE" "$s" 'no longer shadows a violation'
  done < <(printf '%s\n' "${stale[@]}" | sort)
fi

if ((rc == 0)); then
  printf 'fixture git isolation: OK (%d isolated, %d baselined; %d git-running suites read no host config, %d baselined)\n' \
    "${#covered[@]}" "${#BASELINED[@]}" "$gchecked" "${#GBASELINED[@]}"
fi
exit "$rc"
