#!/usr/bin/env bash
# Regression tests for splice-assets.sh (self-contained, ships with the plugin).
#
# Black-box: every case invokes the script as a subprocess and asserts on the exit
# code, the message stream, and the bytes of the lesson file. Fixtures are built
# with printf under one mktemp root that an EXIT trap removes.
#
# Case 4d is the one exception: it drives `splice-assets.awk` directly. The script
# validates that every present marker's asset is a readable non-empty regular file
# before awk opens that same path, so no black-box run can deterministically reach
# the awk program's read-error branch. Driving the build half on its own is what
# pins that branch.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/splice-assets.sh"
AWK_PROGRAM="$SCRIPT_DIR/splice-assets.awk"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

ERRFILE="$TEST_TMPDIR/stderr.txt"
RC=0
OUT=""
ERR=""

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3, actual: $2" ;;
  esac
}
assert_same_file() {
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1" "files differ: $2 vs $3"; fi
}

# dir_listing <dir>: every entry directly inside <dir>, dotfiles included, sorted.
# The temp file the script builds is a sibling dotfile of the lesson, so a listing
# taken before and after a run is what proves none survived.
dir_listing() {
  find "$1" -mindepth 1 -maxdepth 1 | sort
}

# run_script <arg>... : sets RC, OUT (stdout), ERR (stderr).
run_script() {
  RC=0
  OUT=$(bash "$SCRIPT" "$@" 2>"$ERRFILE") || RC=$?
  ERR=$(<"$ERRFILE")
}

# mk_case <name> : builds <root>/<name>/{concept,assets} and echoes the case root.
mk_case() {
  local root="$TEST_TMPDIR/$1"
  mkdir -p "$root/concept" "$root/assets"
  printf '%s' "$root"
}

# --- Case 1: both markers present, both assets spliced ----------------------

C1="$(mk_case c1)"
L1="$C1/concept/lesson.html"
printf '<!doctype html>\n<style>\n/* SPLICE:STYLE */\n</style>\n<script>\n/* SPLICE:QUIZ */\n</script>\n<p>tail</p>\n' >"$L1"
printf 'body { color: red; }\n.card { top: 0; }\n' >"$C1/assets/lesson.css"
printf 'window.quiz = 1;\n' >"$C1/assets/quiz.js"
printf '<!doctype html>\n<style>\nbody { color: red; }\n.card { top: 0; }\n</style>\n<script>\nwindow.quiz = 1;\n</script>\n<p>tail</p>\n' >"$C1/expected.html"

C1_LS_BEFORE="$(dir_listing "$C1/concept")"
run_script "$L1" "$C1/assets"
C1_LS_AFTER="$(dir_listing "$C1/concept")"
assert_exit "both markers: exit 0" 0 "$RC"
assert_same_file "both markers: lesson matches the expected splice" "$L1" "$C1/expected.html"
# Case 5 (half): no temp file survives a successful run.
assert_eq "both markers: lesson directory listing unchanged" "$C1_LS_BEFORE" "$C1_LS_AFTER"

# --- Case 2: STYLE marker only, quiz.js absent ------------------------------

C2="$(mk_case c2)"
L2="$C2/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>\n<p>no quiz here</p>\n' >"$L2"
printf 'body { margin: 0; }\n' >"$C2/assets/lesson.css"
printf '<style>\nbody { margin: 0; }\n</style>\n<p>no quiz here</p>\n' >"$C2/expected.html"

run_script "$L2" "$C2/assets"
assert_exit "style-only lesson: exit 0 with quiz.js absent" 0 "$RC"
assert_same_file "style-only lesson: only the style marker was replaced" "$L2" "$C2/expected.html"

# --- Case 3: QUIZ marker present, quiz.js missing ---------------------------

C3="$(mk_case c3)"
L3="$C3/concept/lesson.html"
printf '<script>\n/* SPLICE:QUIZ */\n</script>\n' >"$L3"
cp "$L3" "$C3/before.html"

C3_LS_BEFORE="$(dir_listing "$C3/concept")"
run_script "$L3" "$C3/assets"
C3_LS_AFTER="$(dir_listing "$C3/concept")"
assert_exit "missing asset: exit 1" 1 "$RC"
assert_contains "missing asset: stderr names quiz.js" "$ERR" "quiz.js"
assert_same_file "missing asset: lesson byte-identical" "$L3" "$C3/before.html"
# Case 5 (half): no temp file survives a refused run.
assert_eq "missing asset: lesson directory listing unchanged" "$C3_LS_BEFORE" "$C3_LS_AFTER"

# --- Case 3b: asset is a directory, and asset is an empty file --------------

C3B="$(mk_case c3b)"
L3B="$C3B/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>\n' >"$L3B"
cp "$L3B" "$C3B/before.html"
mkdir -p "$C3B/assets/lesson.css"

run_script "$L3B" "$C3B/assets"
assert_exit "asset is a directory: exit 1" 1 "$RC"
assert_contains "asset is a directory: stderr names lesson.css" "$ERR" "lesson.css"
assert_same_file "asset is a directory: lesson byte-identical" "$L3B" "$C3B/before.html"

rmdir "$C3B/assets/lesson.css"
: >"$C3B/assets/lesson.css"
run_script "$L3B" "$C3B/assets"
assert_exit "asset is empty: exit 1" 1 "$RC"
assert_contains "asset is empty: stderr names lesson.css" "$ERR" "lesson.css"
assert_same_file "asset is empty: lesson byte-identical" "$L3B" "$C3B/before.html"

# --- Case 3c: a marker occurring twice --------------------------------------

C3C="$(mk_case c3c)"
L3C="$C3C/concept/lesson.html"
printf '<script>\n/* SPLICE:QUIZ */\n</script>\n<script>\n/* SPLICE:QUIZ */\n</script>\n' >"$L3C"
cp "$L3C" "$C3C/before.html"
printf 'window.quiz = 1;\n' >"$C3C/assets/quiz.js"

run_script "$L3C" "$C3C/assets"
assert_exit "duplicated marker: exit 1" 1 "$RC"
assert_contains "duplicated marker: stderr names the marker" "$ERR" "/* SPLICE:QUIZ */"
assert_contains "duplicated marker: stderr names the count" "$ERR" "occurs 2 times"
assert_same_file "duplicated marker: lesson byte-identical" "$L3C" "$C3C/before.html"

# --- Case 3d: the same marker twice on ONE line -----------------------------
# Counting matching LINES rather than occurrences would read this as a single
# marker, splice it once, and silently drop the second one.

C3D="$(mk_case c3d)"
L3D="$C3D/concept/lesson.html"
printf '<script>\n/* SPLICE:QUIZ */ /* SPLICE:QUIZ */\n</script>\n' >"$L3D"
cp "$L3D" "$C3D/before.html"
printf 'window.quiz = 1;\n' >"$C3D/assets/quiz.js"

run_script "$L3D" "$C3D/assets"
assert_exit "marker twice on one line: exit 1" 1 "$RC"
assert_contains "marker twice on one line: stderr names the count" "$ERR" "occurs 2 times"
assert_same_file "marker twice on one line: lesson byte-identical" "$L3D" "$C3D/before.html"

# --- Case 3e: both markers on ONE line --------------------------------------
# Each marker line is replaced whole, so a line carrying both could only ever
# deliver one of the two assets. Caught by the marker-alone rule, which reports
# the offending line and so names both markers in passing.

C3E="$(mk_case c3e)"
L3E="$C3E/concept/lesson.html"
printf '<style>/* SPLICE:STYLE */</style><script>/* SPLICE:QUIZ */</script>\n' >"$L3E"
cp "$L3E" "$C3E/before.html"
printf 'body { margin: 0; }\n' >"$C3E/assets/lesson.css"
printf 'window.quiz = 1;\n' >"$C3E/assets/quiz.js"

run_script "$L3E" "$C3E/assets"
assert_exit "both markers on one line: exit 1" 1 "$RC"
assert_contains "both markers on one line: stderr reports the shared line" "$ERR" "shares its line"
assert_contains "both markers on one line: stderr names the style marker" "$ERR" "/* SPLICE:STYLE */"
assert_contains "both markers on one line: stderr names the quiz marker" "$ERR" "/* SPLICE:QUIZ */"
assert_same_file "both markers on one line: lesson byte-identical" "$L3E" "$C3E/before.html"

# --- Case 3f: one marker sharing its line with its own tags -----------------
# The count is 1 and no line carries both markers, so only the marker-alone rule
# refuses this. Replacing the line whole would drop the tags with exit 0.

C3F="$(mk_case c3f)"
L3F="$C3F/concept/lesson.html"
printf '<style>/* SPLICE:STYLE */</style>\n' >"$L3F"
cp "$L3F" "$C3F/before.html"
printf 'body { margin: 0; }\n' >"$C3F/assets/lesson.css"

C3F_LS_BEFORE="$(dir_listing "$C3F/concept")"
run_script "$L3F" "$C3F/assets"
C3F_LS_AFTER="$(dir_listing "$C3F/concept")"
assert_exit "marker sharing its line with its tags: exit 1" 1 "$RC"
assert_contains "marker sharing its line with its tags: stderr names the marker" "$ERR" "/* SPLICE:STYLE */"
assert_same_file "marker sharing its line with its tags: lesson byte-identical" "$L3F" "$C3F/before.html"
assert_eq "marker sharing its line with its tags: lesson directory listing unchanged" "$C3F_LS_BEFORE" "$C3F_LS_AFTER"

# --- Case 3g: an indented marker line still splices -------------------------
# The marker-alone rule compares with all whitespace stripped, which is what
# keeps indentation legal. The positive half of case 3f.

C3G="$(mk_case c3g)"
L3G="$C3G/concept/lesson.html"
printf '<style>\n    /* SPLICE:STYLE */\t\n</style>\n' >"$L3G"
printf 'body { margin: 0; }\n' >"$C3G/assets/lesson.css"
printf '<style>\nbody { margin: 0; }\n</style>\n' >"$C3G/expected.html"

run_script "$L3G" "$C3G/assets"
assert_exit "indented marker line: exit 0" 0 "$RC"
assert_same_file "indented marker line: asset spliced in its place" "$L3G" "$C3G/expected.html"

# --- Case 4: usage errors ---------------------------------------------------

C4="$(mk_case c4)"
L4="$C4/concept/lesson.html"
printf '<p>plain</p>\n' >"$L4"

run_script
assert_exit "zero arguments: exit 2" 2 "$RC"
assert_contains "zero arguments: usage on stderr" "$ERR" "Usage:"

run_script "$L4"
assert_exit "one argument: exit 2" 2 "$RC"
assert_contains "one argument: usage on stderr" "$ERR" "Usage:"

run_script "$L4" "$C4/assets" "extra"
assert_exit "three arguments: exit 2" 2 "$RC"
assert_contains "three arguments: usage on stderr" "$ERR" "Usage:"

run_script "$C4/concept/absent.html" "$C4/assets"
assert_exit "nonexistent lesson: exit 2" 2 "$RC"

run_script "$C4/concept" "$C4/assets"
assert_exit "lesson path is a directory: exit 2" 2 "$RC"

run_script "$L4" "$C4/absent-assets"
assert_exit "nonexistent assets dir: exit 2" 2 "$RC"

run_script "$L4" "$L4"
assert_exit "assets path is a file: exit 2" 2 "$RC"

run_script --help
assert_exit "--help exits 0" 0 "$RC"
assert_contains "--help prints usage on stdout" "$OUT" "Usage:"

run_script -h
assert_exit "-h exits 0" 0 "$RC"
assert_contains "-h prints usage on stdout" "$OUT" "Usage:"

# --- Case 4b: a read-only lesson is a usage error, refused before any write --
# Writability is validated up front so the "every validation runs before any
# write" claim in the script header stays literally true.

C4B="$(mk_case c4b)"
L4B="$C4B/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>\n' >"$L4B"
cp "$L4B" "$C4B/before.html"
printf 'body { margin: 0; }\n' >"$C4B/assets/lesson.css"
chmod a-w "$L4B"
if [[ -w "$L4B" ]]; then
  # discriminating-skip-ok: host-gated, this filesystem keeps the owner's write bit after chmod a-w
  printf 'SKIP: read-only lesson (chmod a-w left the file writable here)\n'
else
  run_script "$L4B" "$C4B/assets"
  assert_exit "read-only lesson: exit 2" 2 "$RC"
  assert_contains "read-only lesson: usage on stderr" "$ERR" "Usage:"
  assert_same_file "read-only lesson: lesson byte-identical" "$L4B" "$C4B/before.html"
fi
# Restored so the EXIT trap can remove the fixture tree.
chmod u+w "$L4B"

# --- Case 4c: a failed build exits 1 and leaves no temp file ----------------
# A stub awk on PATH is the only way to reach the build-failure branch and the
# temp-file cleanup trap. Nothing else in the suite exercises either.

C4C="$(mk_case c4c)"
L4C="$C4C/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>\n' >"$L4C"
cp "$L4C" "$C4C/before.html"
printf 'body { margin: 0; }\n' >"$C4C/assets/lesson.css"
STUB_BIN="$C4C/stub-bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 3\n' >"$STUB_BIN/awk"
chmod +x "$STUB_BIN/awk"

C4C_LS_BEFORE="$(dir_listing "$C4C/concept")"
RC=0
OUT=$(PATH="$STUB_BIN:$PATH" bash "$SCRIPT" "$L4C" "$C4C/assets" 2>"$ERRFILE") || RC=$?
ERR=$(<"$ERRFILE")
C4C_LS_AFTER="$(dir_listing "$C4C/concept")"
assert_exit "failed build: exit 1" 1 "$RC"
assert_contains "failed build: stderr names the build step" "$ERR" "awk"
assert_same_file "failed build: lesson byte-identical" "$L4C" "$C4C/before.html"
assert_eq "failed build: no temp file survives" "$C4C_LS_BEFORE" "$C4C_LS_AFTER"

# --- Case 4d: a failed asset read during the build exits nonzero ------------
# The one case that drives splice-assets.awk rather than the script (header).
# A directory in place of lesson.css is a read failure the script's validation
# would refuse first, so the build half is driven on its own here. gawk returns
# -1 from getline and this program then names the file; mawk, the awk on Ubuntu
# CI, raises its own fatal read error instead, whose text is not guaranteed to
# carry the path. Both are nonzero, so only the exit code is asserted
# unconditionally.

C4D="$(mk_case c4d)"
L4D="$C4D/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>\n' >"$L4D"
mkdir -p "$C4D/assets/lesson.css"

RC=0
OUT=$(A="$C4D/assets" awk -v BINMODE=3 -f "$AWK_PROGRAM" "$L4D" 2>"$ERRFILE") || RC=$?
ERR=$(<"$ERRFILE")
if [[ "$RC" -ne 0 ]]; then
  pass "asset read error: the build half exits nonzero"
else
  fail "asset read error: the build half exits nonzero" "expected a nonzero exit, got $RC"
fi
if awk --version 2>/dev/null | head -1 | grep -q 'GNU Awk'; then
  assert_contains "asset read error: stderr names lesson.css" "$ERR" "lesson.css"
elif [[ -n "$ERR" ]]; then
  # discriminating-skip-ok: host-gated, only gawk reaches this program's own read-error branch
  pass "asset read error: the failing read is reported on stderr (awk's own message)"
else
  fail "asset read error: the failing read is reported on stderr (awk's own message)" "stderr was empty"
fi

# --- Case 6: a CRLF lesson keeps its carriage returns on unspliced lines ----

C6="$(mk_case c6)"
L6="$C6/concept/lesson.html"
printf '<style>\r\n/* SPLICE:STYLE */\r\n</style>\r\n<script>\r\n/* SPLICE:QUIZ */\r\n</script>\r\n<p>tail</p>\r\n' >"$L6"
printf 'body { color: red; }\n' >"$C6/assets/lesson.css"
printf 'window.quiz = 1;\n' >"$C6/assets/quiz.js"

printf '<style>\r\nbody { color: red; }\n</style>\r\n<script>\r\nwindow.quiz = 1;\n</script>\r\n<p>tail</p>\r\n' >"$C6/expected.html"

# Carriage returns are counted as BYTES, with tr rather than grep: Git Bash's grep
# opens a file in text mode, so a CR pattern can never match and a CR count taken
# that way would report 0 on every host that matters here.
cr_bytes() { tr -dc '\r' <"$1" | wc -c; }

CR_BEFORE=$(cr_bytes "$L6")
run_script "$L6" "$C6/assets"
CR_AFTER=$(cr_bytes "$L6")
assert_exit "CRLF lesson: exit 0" 0 "$RC"
# The two marker lines are gone and the LF-only assets bring no carriage returns,
# so every remaining CR belongs to an untouched line of the original lesson.
assert_eq "CRLF lesson: unspliced lines keep their carriage returns" "$((CR_BEFORE - 2))" "$CR_AFTER"
assert_same_file "CRLF lesson: output is byte-exact" "$L6" "$C6/expected.html"

# --- Case 6b: no trailing newline on either the asset or the lesson ---------

C6B="$(mk_case c6b)"
L6B="$C6B/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>' >"$L6B"
printf 'body { margin: 0; }' >"$C6B/assets/lesson.css"
printf '<style>\nbody { margin: 0; }\n</style>\n' >"$C6B/expected.html"

run_script "$L6B" "$C6B/assets"
assert_exit "no trailing newline: exit 0" 0 "$RC"
assert_same_file "no trailing newline: asset and lesson both gain one" "$L6B" "$C6B/expected.html"
assert_eq "no trailing newline: output ends in a newline" "" "$(tail -c 1 "$L6B")"

# --- Case 7: a backslash-form assets path (Git Bash only) -------------------
# The assets path reaches awk through ENVIRON, so its backslashes are not read as
# escape sequences. Only a Windows host can produce such a path.

if [[ "$(uname -o 2>/dev/null)" == "Msys" ]] && command -v cygpath >/dev/null 2>&1; then
  C7="$(mk_case c7)"
  L7="$C7/concept/lesson.html"
  printf '<style>\n/* SPLICE:STYLE */\n</style>\n' >"$L7"
  printf 'body { color: blue; }\n' >"$C7/assets/lesson.css"
  printf '<style>\nbody { color: blue; }\n</style>\n' >"$C7/expected.html"
  WIN_ASSETS="$(cygpath -w "$C7/assets")"
  run_script "$L7" "$WIN_ASSETS"
  assert_exit "backslash assets path: exit 0" 0 "$RC"
  assert_same_file "backslash assets path: asset spliced verbatim" "$L7" "$C7/expected.html"
else
  # discriminating-skip-ok: host-gated, Git Bash only
  printf 'SKIP: backslash assets path (not a Git Bash host)\n'
fi

# --- Case 8: the guardrails bypass guard allows the documented invocation ---
# The point of the change: the command a coach runs carries no redirect and no
# staged move, so block-hook-bypass.sh lets it through, while the recipe it
# replaces is still refused.

GUARDRAILS_DIR="$SCRIPT_DIR/../../../../guardrails"
HOOK="$GUARDRAILS_DIR/hooks/block-hook-bypass.sh"

# command_json <command-string>: the PreToolUse Bash payload the hook reads on
# stdin. Backslash first, then the quote, so an escape is never re-escaped.
command_json() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$s"
}

probe_hook() {
  RC=0
  # `env` carries the empty CLAUDE_PROJECT_DIR, which the guardrails suite treats as a
  # pin: the guard has a scratch-root default gated on a known project root, so a project
  # dir merely inherited from the surrounding shell would decide the verdict.
  OUT=$(env CLAUDE_PROJECT_DIR= bash "$HOOK" <<<"$(command_json "$1")" 2>"$ERRFILE") || RC=$?
  ERR=$(<"$ERRFILE")
}

# shellcheck disable=SC2016  # `${CLAUDE_PLUGIN_ROOT}` stays literal: the guard is driven with
# the command string exactly as lessons.md writes it, before the harness substitutes anything.
NEW_INVOCATION='bash "${CLAUDE_PLUGIN_ROOT}/skills/teach/scripts/splice-assets.sh" "/c/Users/Test User/Claude Learning/proj/topic/rust/concepts/ownership/lesson.html" "/c/Users/Test User/Claude Learning/proj/topic/rust/assets"'
OLD_RECIPE='awk -v A="/c/ws/assets" "/\/\* SPLICE:STYLE \*\// { next } { print }" lesson.html > lesson.html.tmp && mv lesson.html.tmp lesson.html'

if [[ -d "$GUARDRAILS_DIR" ]]; then
  if [[ -f "$HOOK" ]]; then
    probe_hook "$NEW_INVOCATION"
    assert_exit "guard allows the documented invocation" 0 "$RC"
    probe_hook "$OLD_RECIPE"
    assert_exit "guard still blocks the staged-move recipe" 2 "$RC"
  else
    fail "guardrails hook is missing" "expected $HOOK to exist beside the guardrails plugin"
  fi
else
  # discriminating-skip-ok: guardrails plugin not checked out
  printf 'SKIP: guardrails probe (the guardrails plugin is not checked out)\n'
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
