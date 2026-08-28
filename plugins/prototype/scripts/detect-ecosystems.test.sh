#!/usr/bin/env bash
# Self-contained tests for detect-ecosystems.sh (no external test lib, since
# this ships with the plugin; fixtures are built inline in a tmpdir).
#
# What this suite is for. The detector is the preamble command both prototype
# skills run before anything else, through the `!` backtick form in their
# SKILL.md. It therefore has two contracts a reader of the 18-line script would
# not guess:
#
#   1. It must ALWAYS exit 0 and always print something. The skill bodies wrap
#      it as `... 2>/dev/null || echo "none detected"`, so a nonzero exit is
#      survivable but a nonzero exit that also printed a partial list would
#      show the user a truncated ecosystem set with no signal that it was cut.
#      "none detected" on stdout, exit 0, is the empty answer.
#   2. An unmatched glob must never leak its own pattern. `*.sln` with no match
#      stays the literal string `*.sln` under bash's default (no nullglob), and
#      the whole reason this script exists rather than an `ls *.sln` is that the
#      literal must not reach the output. That is the case a reader is most
#      likely to break by "simplifying" the loop.
#
# Anchoring is the third contract: markers live at the project ROOT, and the
# preamble may run from any cwd, so the script resolves a root itself. The
# precedence chain is CLAUDE_PROJECT_DIR, then the git toplevel, then the cwd,
# and a nonexistent CLAUDE_PROJECT_DIR must degrade to the cwd rather than abort.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect-ecosystems.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

# mkfixture <name> [marker ...] builds a project root holding exactly these markers.
# Echoes the absolute path so a case can name it in one line.
mkfixture() {
  local name="$1"
  shift
  local dir="$TEST_TMPDIR/$name"
  mkdir -p "$dir"
  local m
  for m in "$@"; do
    : >"$dir/$m"
  done
  printf '%s\n' "$dir"
}

# run_in <root> is the ordinary invocation: CLAUDE_PROJECT_DIR names the root and
# the cwd is deliberately somewhere else, which is the real preamble situation.
run_in() {
  (cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$1" bash "$DETECT" 2>/dev/null)
}

# --- 1. The empty answer ------------------------------------------------------

EMPTY="$(mkfixture empty)"
empty_out="$(run_in "$EMPTY")"
empty_exit=0
run_in "$EMPTY" >/dev/null || empty_exit=$?
assert_equals "empty project prints the empty answer" "none detected" "$empty_out"
assert_exit "empty project still exits 0" 0 "$empty_exit"

# The literal-glob leak. This is the defect the script's own header names, and
# it is invisible in the "none detected" assertion above only because that
# assertion is EXACT. A leak would append the patterns rather than replace the
# message. Both directions are pinned so neither can regress alone.
assert_not_contains "unmatched *.sln does not leak its pattern" "$empty_out" '*.sln'
assert_not_contains "unmatched *.slnx does not leak its pattern" "$empty_out" '*.slnx'

# --- 2. Every marker the script actually detects ------------------------------
# One case per marker so a dropped entry in the glob list names itself. The
# .NET pair is matched by GLOB, the other four by exact name; both halves are
# covered and neither is inferred from the other.

for marker in package.json pyproject.toml Cargo.toml go.mod; do
  one="$(mkfixture "solo-$marker" "$marker")"
  assert_equals "$marker alone is detected" "$marker" "$(run_in "$one")"
done

SLN_ONE="$(mkfixture sln-one MyApp.sln)"
assert_equals "a .sln is detected by glob" "MyApp.sln" "$(run_in "$SLN_ONE")"

SLNX_ONE="$(mkfixture slnx-one MyApp.slnx)"
assert_equals "a .slnx is detected by glob" "MyApp.slnx" "$(run_in "$SLNX_ONE")"

# A marker name that is a PREFIX or SUFFIX of a real one must not match: the
# four exact-name markers are not globs, and the two globs are anchored on the
# extension. The fixture also carries plausible NON-marker manifests (Makefile,
# Gemfile, requirements.txt), so widening the marker list fails here instead of
# passing silently.
NEARMISS="$(mkfixture near-miss package.json.bak go.mod.orig mypyproject.toml Cargo.toml.lock notes.slnx.txt Makefile Gemfile requirements.txt)"
assert_equals "near-miss filenames detect nothing" "none detected" "$(run_in "$NEARMISS")"

# --- 3. Multi-ecosystem tree, and the order it reports ------------------------
# The output order is the loop's glob order, not the filesystem's or sort's, and
# the skills quote the first lines of this output back to the user. Pinning the
# whole block keeps a reordering of the glob list from silently changing what a
# reader sees first.

MULTI="$(mkfixture multi package.json pyproject.toml Cargo.toml go.mod App.sln App.slnx)"
multi_out="$(run_in "$MULTI")"
multi_expected="$(printf '%s\n' App.slnx App.sln package.json pyproject.toml Cargo.toml go.mod)"
assert_equals "multi-ecosystem tree reports every marker in glob order" "$multi_expected" "$multi_out"
assert_not_contains "a populated tree never prints the empty answer" "$multi_out" "none detected"

# A partial tree exercises the same loop with FAILING tests interleaved between
# passing ones. `[[ -e … ]] && found+=(…)` leaves a nonzero status behind on
# every miss, including the final iteration, and the script runs under `set -e`.
PARTIAL="$(mkfixture partial App.slnx)"
partial_exit=0
partial_out="$(run_in "$PARTIAL")" || partial_exit=$?
assert_equals "a match on the FIRST glob with all later misses still reports" "App.slnx" "$partial_out"
assert_exit "trailing misses under set -e do not abort the script" 0 "$partial_exit"

# --- 4. Multiple files behind one glob ----------------------------------------

MANY_SLN="$(mkfixture many-sln Zebra.sln Alpha.sln Middle.slnx)"
many_expected="$(printf '%s\n' Middle.slnx Alpha.sln Zebra.sln)"
assert_equals "every glob match is listed, sorted within its glob" "$many_expected" "$(run_in "$MANY_SLN")"

# --- 5. Filenames the loop could mangle ---------------------------------------
# The found list is an ARRAY expanded as "${found[@]}". A space-bearing glob
# match is the case that a `for f in $(...)` or an unquoted expansion splits.

SPACED="$(mkfixture spaced)"
: >"$SPACED/My Big App.sln"
assert_equals "a space in a glob match survives as one entry" "My Big App.sln" "$(run_in "$SPACED")"

SPACED_MULTI="$(mkfixture spaced-multi go.mod)"
: >"$SPACED_MULTI/My Big App.sln"
spaced_multi_expected="$(printf '%s\n' 'My Big App.sln' go.mod)"
assert_equals "a space-bearing match does not split the rest of the list" \
  "$spaced_multi_expected" "$(run_in "$SPACED_MULTI")"

# --- 6. What counts as present: -e, one directory level -----------------------

NESTED="$(mkfixture nested)"
mkdir -p "$NESTED/services/api"
: >"$NESTED/services/api/package.json"
assert_equals "a marker below the root is not detected (no recursion)" \
  "none detected" "$(run_in "$NESTED")"

DIRMARKER="$(mkfixture dir-marker)"
mkdir -p "$DIRMARKER/package.json"
assert_equals "a DIRECTORY named like a marker is detected (-e, not -f)" \
  "package.json" "$(run_in "$DIRMARKER")"

SYMLINKED="$(mkfixture symlinked)"
: >"$TEST_TMPDIR/real-package.json"
ln -s "$TEST_TMPDIR/real-package.json" "$SYMLINKED/package.json"
ln -s "$TEST_TMPDIR/no-such-target" "$SYMLINKED/go.mod"
sym_out="$(run_in "$SYMLINKED")"
assert_contains "a symlink to a live marker is detected" "$sym_out" "package.json"
assert_not_contains "a BROKEN symlink is not detected" "$sym_out" "go.mod"

# --- 7. Root anchoring: CLAUDE_PROJECT_DIR wins -------------------------------

WINS="$(mkfixture anchor-wins Cargo.toml)"
DECOY="$(mkfixture anchor-decoy package.json)"
anchor_out="$(cd "$DECOY" && CLAUDE_PROJECT_DIR="$WINS" bash "$DETECT" 2>/dev/null)"
assert_equals "CLAUDE_PROJECT_DIR outranks the cwd" "Cargo.toml" "$anchor_out"

# An EMPTY CLAUDE_PROJECT_DIR is the unset case: the script uses `:-`, so an
# exported-but-blank variable falls through to the git/cwd chain instead of
# anchoring on the filesystem root.
blank_out="$(cd "$DECOY" && env CLAUDE_PROJECT_DIR= GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$DETECT" 2>/dev/null)"
assert_equals "an empty CLAUDE_PROJECT_DIR is treated as unset" "package.json" "$blank_out"

# --- 8. Root anchoring: the git toplevel ---------------------------------------

GITREPO="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITREPO/deep/nested"
git -C "$GITREPO" init -q
: >"$GITREPO/Cargo.toml"
: >"$GITREPO/deep/nested/package.json"
git_out="$(cd "$GITREPO/deep/nested" && env -u CLAUDE_PROJECT_DIR bash "$DETECT" 2>/dev/null)"
assert_equals "without CLAUDE_PROJECT_DIR the git toplevel is the root" "Cargo.toml" "$git_out"
assert_not_contains "the cwd's own marker is not reported from a subdirectory" "$git_out" "package.json"

# --- 9. Root anchoring: the cwd fallback ---------------------------------------
# GIT_CEILING_DIRECTORIES makes this deterministic: without it the case would
# pass or fail on whether the machine's TMPDIR happens to sit inside a checkout.

NOGIT="$(mkfixture nogit pyproject.toml)"
nogit_out="$(cd "$NOGIT" && env -u CLAUDE_PROJECT_DIR GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$DETECT" 2>/dev/null)"
assert_equals "outside a repo and with no override, the cwd is the root" "pyproject.toml" "$nogit_out"

# --- 10. A CLAUDE_PROJECT_DIR that does not exist -------------------------------
# The `cd … || true` is load-bearing: under `set -e` a failed cd would abort with
# no output at all, and the skill preamble would show the user nothing. The
# documented degradation is "stay in the cwd and answer from there", quietly.

GHOST="$(mkfixture ghost-cwd go.mod)"
ghost_exit=0
ghost_out="$(cd "$GHOST" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/does-not-exist" bash "$DETECT" 2>/dev/null)" || ghost_exit=$?
assert_equals "a nonexistent CLAUDE_PROJECT_DIR degrades to the cwd" "go.mod" "$ghost_out"
assert_exit "a nonexistent CLAUDE_PROJECT_DIR does not abort" 0 "$ghost_exit"

# The cd failure must also stay off stderr. The skills redirect stderr away, so
# a leak is not user-visible there, but it is visible to every other caller.
ghost_err="$(cd "$GHOST" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/does-not-exist" bash "$DETECT" 2>&1 >/dev/null)"
assert_equals "the failed cd prints nothing on stderr" "" "$ghost_err"

# --- 11. Arguments -------------------------------------------------------------
# The script reads no arguments, but the skill grants are `…/detect-ecosystems.sh:*`
# and the wrappers forward "$@", so anything a caller appends lands here. It must
# be inert rather than fatal.

args_exit=0
args_out="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$MULTI" bash "$DETECT" --bogus extra 2>/dev/null)" || args_exit=$?
assert_equals "unread arguments do not change the answer" "$multi_expected" "$args_out"
assert_exit "unread arguments do not fail the script" 0 "$args_exit"

# --- 12. Output shape ----------------------------------------------------------
# One marker per line, newline-terminated, nothing else on stdout. A consumer
# pipes this into `head`, so a trailing-newline regression would join the last
# marker to whatever follows.

raw="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$SLN_ONE" bash "$DETECT" 2>/dev/null | od -c | tr -s ' ')"
assert_contains "output is newline-terminated" "$raw" 'M y A p p . s l n \n'

line_count="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$MULTI" bash "$DETECT" 2>/dev/null | wc -l | tr -d ' ')"
assert_equals "six markers print on exactly six lines" "6" "$line_count"

clean_err="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$MULTI" bash "$DETECT" 2>&1 >/dev/null)"
assert_equals "a normal run prints nothing on stderr" "" "$clean_err"

# --- Report --------------------------------------------------------------------

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
echo "All detect-ecosystems.sh checks passed."
