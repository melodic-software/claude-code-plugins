#!/usr/bin/env bash

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

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3, actual: $2" ;;
  esac
}
assert_same_file() {
  if cmp -s "$2" "$3"; then pass "$1"; else fail "$1" "files differ: $2 vs $3"; fi
}

dir_listing() {
  find "$1" -mindepth 1 -maxdepth 1 | sort
}

run_script() {
  RC=0
  OUT=$(bash "$SCRIPT" "$@" 2>"$ERRFILE") || RC=$?
  ERR=$(<"$ERRFILE")
}

mk_case() {
  local root="$TEST_TMPDIR/$1"
  mkdir -p "$root/concept" "$root/assets"
  printf '%s' "$root"
}


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
assert_eq "both markers: lesson directory listing unchanged" "$C1_LS_BEFORE" "$C1_LS_AFTER"


C2="$(mk_case c2)"
L2="$C2/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>\n<p>no quiz here</p>\n' >"$L2"
printf 'body { margin: 0; }\n' >"$C2/assets/lesson.css"
printf '<style>\nbody { margin: 0; }\n</style>\n<p>no quiz here</p>\n' >"$C2/expected.html"

run_script "$L2" "$C2/assets"
assert_exit "style-only lesson: exit 0 with quiz.js absent" 0 "$RC"
assert_same_file "style-only lesson: only the style marker was replaced" "$L2" "$C2/expected.html"


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
assert_eq "missing asset: lesson directory listing unchanged" "$C3_LS_BEFORE" "$C3_LS_AFTER"


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


C3D="$(mk_case c3d)"
L3D="$C3D/concept/lesson.html"
printf '<script>\n/* SPLICE:QUIZ */ /* SPLICE:QUIZ */\n</script>\n' >"$L3D"
cp "$L3D" "$C3D/before.html"
printf 'window.quiz = 1;\n' >"$C3D/assets/quiz.js"

run_script "$L3D" "$C3D/assets"
assert_exit "marker twice on one line: exit 1" 1 "$RC"
assert_contains "marker twice on one line: stderr names the count" "$ERR" "occurs 2 times"
assert_same_file "marker twice on one line: lesson byte-identical" "$L3D" "$C3D/before.html"


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


C3G="$(mk_case c3g)"
L3G="$C3G/concept/lesson.html"
printf '<style>\n    /* SPLICE:STYLE */\t\n</style>\n' >"$L3G"
printf 'body { margin: 0; }\n' >"$C3G/assets/lesson.css"
printf '<style>\nbody { margin: 0; }\n</style>\n' >"$C3G/expected.html"

run_script "$L3G" "$C3G/assets"
assert_exit "indented marker line: exit 0" 0 "$RC"
assert_same_file "indented marker line: asset spliced in its place" "$L3G" "$C3G/expected.html"


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
chmod u+w "$L4B"


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
if grep -q 'GNU Awk' < <(awk --version 2>/dev/null | head -1); then
  assert_contains "asset read error: stderr names lesson.css" "$ERR" "lesson.css"
elif [[ -n "$ERR" ]]; then
  # discriminating-skip-ok: host-gated, only gawk reaches this program's own read-error branch
  pass "asset read error: the failing read is reported on stderr (awk's own message)"
else
  fail "asset read error: the failing read is reported on stderr (awk's own message)" "stderr was empty"
fi


C6="$(mk_case c6)"
L6="$C6/concept/lesson.html"
printf '<style>\r\n/* SPLICE:STYLE */\r\n</style>\r\n<script>\r\n/* SPLICE:QUIZ */\r\n</script>\r\n<p>tail</p>\r\n' >"$L6"
printf 'body { color: red; }\n' >"$C6/assets/lesson.css"
printf 'window.quiz = 1;\n' >"$C6/assets/quiz.js"

printf '<style>\r\nbody { color: red; }\n</style>\r\n<script>\r\nwindow.quiz = 1;\n</script>\r\n<p>tail</p>\r\n' >"$C6/expected.html"

cr_bytes() { tr -dc '\r' <"$1" | wc -c; }

CR_BEFORE=$(cr_bytes "$L6")
run_script "$L6" "$C6/assets"
CR_AFTER=$(cr_bytes "$L6")
assert_exit "CRLF lesson: exit 0" 0 "$RC"
assert_eq "CRLF lesson: unspliced lines keep their carriage returns" "$((CR_BEFORE - 2))" "$CR_AFTER"
assert_same_file "CRLF lesson: output is byte-exact" "$L6" "$C6/expected.html"


C6B="$(mk_case c6b)"
L6B="$C6B/concept/lesson.html"
printf '<style>\n/* SPLICE:STYLE */\n</style>' >"$L6B"
printf 'body { margin: 0; }' >"$C6B/assets/lesson.css"
printf '<style>\nbody { margin: 0; }\n</style>\n' >"$C6B/expected.html"

run_script "$L6B" "$C6B/assets"
assert_exit "no trailing newline: exit 0" 0 "$RC"
assert_same_file "no trailing newline: asset and lesson both gain one" "$L6B" "$C6B/expected.html"
assert_eq "no trailing newline: output ends in a newline" "" "$(tail -c 1 "$L6B")"


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

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
