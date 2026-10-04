#!/usr/bin/env bash
# Regression tests for derivable-list.py (assertions from test-helpers.sh beside
# this file). Every fixture is a throwaway git repo under one mktemp -d root,
# isolated from any inherited git environment. Expected counts are worked out
# by hand from each fixture's entries and its tracked files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

host_path() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
SCRIPT="$(host_path "$SCRIPT_DIR/derivable-list.py")"

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

if ! python3 -c '' >/dev/null 2>&1; then
  echo "SKIP: python3 not installed" >&2
  exit 0
fi

dl() { MSYS_NO_PATHCONV=1 python3 "$SCRIPT" "$@"; }

new_fixture() {
  local fx="$TEST_TMPDIR/$1"
  mkdir -p "$fx"
  git -C "$fx" init -q
  printf '%s' "$fx"
}
# put FX RELPATH LINE...: write each LINE, LF-terminated, to the file.
put() {
  local fx="$1" rel="$2"
  shift 2
  mkdir -p "$(dirname "$fx/$rel")"
  printf '%s\n' "$@" >"$fx/$rel"
}
stage() { git -C "$1" add -A; }
# row KIND OUT: the rows of OUT whose first field is KIND.
row() { printf '%s\n' "$2" | awk -F'\t' -v k="$1" '$1 == k' || true; }
count_rows() { if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }
# plugin_dirs FX NAME...: a tracked plugin.json under plugins/NAME for each NAME.
plugin_dirs() {
  local fx="$1" n
  shift
  for n in "$@"; do put "$fx" "plugins/$n/plugin.json" '{}'; done
}

# --- derived list: every entry names a tracked folder ------------------------
FX=$(new_fixture derived)
plugin_dirs "$FX" ant bee cat dog elk fox
put "$FX" registry/index.json '{"name": "kennel", "plugins": [' \
  '{"name": "ant", "source": "./plugins/ant", "category": "dev"},' \
  '{"name": "bee", "source": "./plugins/bee", "category": "dev"},' \
  '{"name": "cat", "source": "./plugins/cat", "category": "ops"},' \
  '{"name": "dog", "source": "./plugins/dog", "category": "ops"},' \
  '{"name": "elk", "source": "./plugins/elk", "category": "ops"},' \
  '{"name": "fox", "source": "./plugins/fox", "category": "dev"}]}'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" registry/index.json)
assert_exit "D1: exit 0" 0 $?
assert_eq "D1: six of six entries name a folder" \
  $'candidate\t6\t6\tregistry/index.json\t/plugins' "$OUT"

# --- one stale entry of six: 5/6 is 83%, still a candidate, entry reported ---
FX=$(new_fixture stale)
plugin_dirs "$FX" ant bee cat dog elk
put "$FX" list.json '["plugins/ant", "plugins/bee", "plugins/cat", "plugins/dog", "plugins/elk", "plugins/gone"]'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" list.json)
assert_eq "S1: five of six is a candidate" $'candidate\t5\t6\tlist.json\t' "$(row candidate "$OUT")"
assert_eq "S1: the dangling entry is listed" $'unnamed\tlist.json\t\t"plugins/gone"' "$(row unnamed "$OUT")"

# --- four of six is 67%: below the threshold ---------------------------------
FX=$(new_fixture below)
plugin_dirs "$FX" ant bee cat dog
put "$FX" list.json '["plugins/ant", "plugins/bee", "plugins/cat", "plugins/dog", "plugins/x", "plugins/y"]'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" list.json)
assert_eq "B1: four of six is below" $'below\t4\t6\tlist.json\t' "$OUT"
assert_eq "B1: no unnamed rows for a list below the threshold" "0" "$(count_rows "$(row unnamed "$OUT")")"

# --- a list of words that name nothing is not derivable ----------------------
FX=$(new_fixture words)
plugin_dirs "$FX" ant
put "$FX" tags.json '{"tags": ["alpha", "beta", "gamma", "delta", "epsilon"]}'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" tags.json)
assert_eq "W1: words name no path" $'below\t0\t5\ttags.json\t/tags' "$OUT"

# --- fewer than five entries is not a list worth flagging --------------------
FX=$(new_fixture short)
plugin_dirs "$FX" ant bee cat dog
put "$FX" list.json '["plugins/ant", "plugins/bee", "plugins/cat", "plugins/dog"]'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" list.json)
assert_eq "N1: four entries is no list" $'no-list\t0\t0\tlist.json\t-' "$OUT"

# --- line mode: a text file listing tracked files, comments skipped ----------
FX=$(new_fixture lines)
put "$FX" lib/a.sh 'a'
put "$FX" lib/b.sh 'b'
put "$FX" lib/c.sh 'c'
put "$FX" lib/d.sh 'd'
put "$FX" lib/e.sh 'e'
put "$FX" copies.txt '# copies kept in sync' '' 'lib/a.sh' 'lib/b.sh' '- lib/c.sh' 'lib/d.sh  # trailing note' 'lib/e.sh'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" copies.txt)
assert_eq "L1: five lines name five tracked files" $'candidate\t5\t5\tcopies.txt\tlines' "$OUT"

# --- entries resolve against the list's own folder too -----------------------
FX=$(new_fixture relative)
for n in 1 2 3 4 5; do put "$FX" "sub/f$n.md" x; done
put "$FX" sub/index.json '["f1.md", "f2.md", "f3.md", "f4.md", "f5.md"]'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" sub/index.json)
assert_eq "R1: names beside the list resolve" $'candidate\t5\t5\tsub/index.json\t' "$OUT"

# --- the tree is the tracked tree: an untracked folder does not count --------
FX=$(new_fixture untracked)
plugin_dirs "$FX" ant bee cat dog
put "$FX" list.json '["plugins/ant", "plugins/bee", "plugins/cat", "plugins/dog", "build/out"]'
stage "$FX"
mkdir -p "$FX/build/out"
: >"$FX/build/out/app.js"
OUT=$(dl --root "$(host_path "$FX")" list.json)
assert_eq "U1: an untracked folder names nothing" $'candidate\t4\t5\tlist.json\t' "$(row candidate "$OUT")"

# --- object keys are a list too ----------------------------------------------
FX=$(new_fixture keys)
plugin_dirs "$FX" ant bee cat dog elk
put "$FX" owners.json '{"owners": {"plugins/ant": "a", "plugins/bee": "b", "plugins/cat": "c", "plugins/dog": "d", "plugins/elk": "e"}}'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" owners.json)
assert_eq "K1: keys that name folders" $'candidate\t5\t5\towners.json\t/owners (keys)' "$OUT"

# --- hostile entry names ------------------------------------------------------
# Each entry would create a marker file, read outside the tree, or split a row
# if the script ever evaluated, stat-ed or printed it raw. Three of the five
# name nothing, so the list is below the threshold; the outside-tree spellings
# must never count as named even though the target exists on disk.
FX=$(new_fixture hostile)
plugin_dirs "$FX" ant bee
mkdir -p "$TEST_TMPDIR/outside"
: >"$TEST_TMPDIR/outside/secret"
# shellcheck disable=SC2016 # literal names, never expanded
put "$FX" list.json '["plugins/ant", "plugins/bee", "$(touch pwned-dollar)", "`touch pwned-tick`", "../outside/secret"]'
stage "$FX"
OUT=$(BASH_COMPAT=51 dl --root "$(host_path "$FX")" list.json)
assert_eq "H1: hostile names count as unnamed" $'below\t2\t5\tlist.json\t' "$OUT"
assert_eq "H1: no marker file was created" "" "$(find "$FX" "$PWD" -maxdepth 1 -name 'pwned-*' 2>/dev/null)"

FX=$(new_fixture hostile-abs)
plugin_dirs "$FX" ant bee cat dog
put "$FX" list.json "[\"plugins/ant\", \"plugins/bee\", \"plugins/cat\", \"plugins/dog\", \"$(host_path "$FX")/plugins/ant\"]"
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" list.json)
assert_eq "H2: an absolute spelling of a tracked folder does not count" \
  $'candidate\t4\t5\tlist.json\t' "$(row candidate "$OUT")"

FX=$(new_fixture hostile-ctl)
plugin_dirs "$FX" ant bee cat dog
put "$FX" list.json '{"a\tb\nc": ["plugins/ant", "plugins/bee", "plugins/cat", "plugins/dog", "bad\u0000\n x"]}'
stage "$FX"
OUT=$(dl --root "$(host_path "$FX")" list.json)
assert_eq "H3: control characters are escaped, every row on one line" \
  $'candidate\t4\t5\tlist.json\t/a\\u0009b\\u000ac\nunnamed\tlist.json\t/a\\u0009b\\u000ac\t"bad\\u0000\\n\\u2028x"' "$OUT"

# A list file whose own name carries shell syntax is read as data.
FX=$(new_fixture hostile-name)
plugin_dirs "$FX" ant bee cat dog elk
# shellcheck disable=SC2016
NAME='lists/$(touch pwned-file).txt'
put "$FX" "$NAME" plugins/ant plugins/bee plugins/cat plugins/dog plugins/elk
stage "$FX"
OUT=$(BASH_COMPAT=51 dl --root "$(host_path "$FX")" "$NAME")
assert_eq "H4: a hostile list name is printed, not run" \
  $'candidate\t5\t5\tlists/$(touch pwned-file).txt\tlines' "$OUT"
assert_eq "H4: no marker file was created" "" "$(find "$FX" -name 'pwned-file' 2>/dev/null)"

# --- arguments that are not tracked files are skipped ------------------------
FX=$(new_fixture skips)
plugin_dirs "$FX" ant
printf 'a\0b' >"$FX/blob.bin"
put "$FX" loose.json '[]'
git -C "$FX" add plugins blob.bin
OUT=$(dl --root "$(host_path "$FX")" ../outside/secret loose.json blob.bin)
assert_exit "K2: skip rows still exit 0" 0 $?
assert_eq "K2: outside, untracked and binary arguments are skipped" \
  $'skip\t../outside/secret\toutside-root\nskip\tloose.json\tuntracked\nskip\tblob.bin\tbinary' "$OUT"

# --- a tracked symlink to a file outside the root is never opened -------------
FX=$(new_fixture symlink)
plugin_dirs "$FX" ant bee cat dog elk
printf '%s\n' '["outside-marker-1", "outside-marker-2", "outside-marker-3", "outside-marker-4", "outside-marker-5"]' \
  >"$TEST_TMPDIR/outside/list.json"
ln -s "$TEST_TMPDIR/outside/list.json" "$FX/link.json"
stage "$FX"
assert_eq "Y1: the fixture tracks a symlink" "120000" "$(git -C "$FX" ls-files -s link.json | cut -d' ' -f1)"
OUT=$(dl --root "$(host_path "$FX")" link.json)
assert_eq "Y1: the symlink is skipped as outside-root" $'skip\tlink.json\toutside-root' "$OUT"
assert_not_contains "Y1: no outside content is printed" "$OUT" "outside-marker"

# --- paths come from a file or stdin, never the command line ------------------
FX=$(new_fixture paths-from)
plugin_dirs "$FX" ant bee cat dog elk
# shellcheck disable=SC2016
NAME='lists/$(touch pwned-from).txt'
put "$FX" "$NAME" plugins/ant plugins/bee plugins/cat plugins/dog plugins/elk
put "$FX" words.txt alpha beta gamma delta epsilon
stage "$FX"
printf '%s\n' "$NAME" words.txt >"$TEST_TMPDIR/paths.txt"
OUT=$(BASH_COMPAT=51 dl --root "$(host_path "$FX")" --paths-from "$(host_path "$TEST_TMPDIR/paths.txt")")
assert_eq "P1: --paths-from FILE reads one path per line" \
  $'candidate\t5\t5\tlists/$(touch pwned-from).txt\tlines\nbelow\t0\t5\twords.txt\tlines' "$OUT"
OUT=$(printf '%s\n' "$NAME" | BASH_COMPAT=51 dl --root "$(host_path "$FX")" --paths-from -)
assert_eq "P2: --paths-from - reads stdin" $'candidate\t5\t5\tlists/$(touch pwned-from).txt\tlines' "$OUT"
assert_eq "P2: no marker file was created" "" "$(find "$FX" "$PWD" -maxdepth 2 -name 'pwned-from' 2>/dev/null)"
OUT=$(printf '' | dl --root "$(host_path "$FX")" --paths-from - 2>&1)
assert_exit "P3: an empty path list exits 2" 2 $?

# --- usage errors ---------------------------------------------------------------
mkdir -p "$TEST_TMPDIR/plain"
dl --root "$(host_path "$TEST_TMPDIR/plain")" x.json >/dev/null 2>&1
assert_exit "E1: not a git work tree exits 2" 2 $?
dl --root "$(host_path "$FX")" >/dev/null 2>&1
assert_exit "E2: no PATH exits 2" 2 $?

echo
echo "derivable-list.test.sh: $((CASE_NUM - FAILED)) passed, $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "derivable-list.test.sh: $FAILED of $CASE_NUM FAILED" >&2
  exit 1
fi
echo "derivable-list.test.sh: all $CASE_NUM passed"
