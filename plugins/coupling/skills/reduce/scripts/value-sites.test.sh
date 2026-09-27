#!/usr/bin/env bash
# Regression tests for value-sites.py (assertions from test-helpers.sh beside
# this file; both ship with the plugin). Every fixture is a throwaway git repo
# under one mktemp -d root, isolated from any inherited git environment.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Git Bash rewrites POSIX arguments for native programs; the suite turns that
# off per call with MSYS_NO_PATHCONV=1, so the script and every fixture root
# are handed over in the host's own spelling up front. `slashes` normalizes
# separators in printed paths. Both are the identity on a host that needs
# neither.
host_path() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
slashes() { printf '%s' "${1//\\//}"; }
SCRIPT="$(host_path "$SCRIPT_DIR/value-sites.py")"

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

vs() { MSYS_NO_PATHCONV=1 python3 "$SCRIPT" "$@"; }

# new_fixture NAME: create an empty git repo and print its path.
new_fixture() {
  local fx="$TEST_TMPDIR/$1"
  mkdir -p "$fx"
  git -C "$fx" init -q
  git -C "$fx" config core.autocrlf false
  printf '%s' "$fx"
}
# put FX RELPATH LINE...: write each LINE (verbatim, LF-terminated) to the file.
put() {
  local fx="$1" rel="$2"
  shift 2
  mkdir -p "$(dirname "$fx/$rel")"
  printf '%s\n' "$@" >"$fx/$rel"
}
stage() { git -C "$1" add -A; }
row_count() { if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi; }
# control_bytes FILE: count bytes below 0x20 other than tab, LF, CR.
control_bytes() { LC_ALL=C tr -d '\t\n\r\040-\377' <"$1" | wc -c | tr -d ' '; }

# --- forms -------------------------------------------------------------------
FX=$(new_fixture forms)
put "$FX" README.md 'Data lives in D:\data\cfg for now.'
put "$FX" setup.sh 'DATA=D:/data/cfg'
put "$FX" app.json '{"dir": "D:\\data\\cfg"}'
put "$FX" run.sh 'cd /d/data/cfg'
put "$FX" wsl.sh 'cd /mnt/d/data/cfg'
put "$FX" other.md 'Unrelated D:\data\cfgx and XD:\data\cfg stay out.'
put "$FX" url.md 'See https://example.com/x/d/data/cfg and https://example.com/d/data/cfg'
stage "$FX"
ROOT=$(host_path "$FX")

rc=0
OUT=$(vs find --old 'D:\data\cfg' --root "$ROOT") || rc=$?
assert_exit "find with sites exits 0" 0 "$rc"
assert_contains "exact form found" "$OUT" $'setup\tREADME.md\t1\t15\texact\tdefault\t'
assert_contains "slash-flipped form found" "$OUT" $'setup\tsetup.sh\t1\t6\tswap\tdefault'
assert_contains "doubled-backslash form found in JSON" "$OUT" $'setup\tapp.json\t1\t10\tdoubled\tdefault'
assert_contains "MSYS form found" "$OUT" $'setup\trun.sh\t1\t4\tmsys\tdefault'
assert_contains "WSL form found" "$OUT" $'setup\twsl.sh\t1\t4\twsl\tdefault'
assert_not_contains "longest overlap wins: WSL site not also an MSYS row" "$OUT" $'wsl.sh\t1\t8'
assert_not_contains "token boundary: no match inside a longer word" "$OUT" "other.md"
assert_not_contains "MSYS form not matched inside a URL path" "$OUT" "url.md"
assert_eq "exactly five sites" "5" "$(row_count "$OUT")"
assert_contains "row text is the line without its newline" "$OUT" $'cd /mnt/d/data/cfg'

# find is read-only
BEFORE=$(git -C "$FX" status --porcelain)
vs find --old 'D:\data\cfg' --root "$ROOT" >/dev/null
vs find --old 'D:\data\cfg' --root "$ROOT" --format summary >/dev/null
AFTER=$(git -C "$FX" status --porcelain)
assert_eq "find leaves the tree unchanged" "$BEFORE" "$AFTER"

# PATH restriction
OUT=$(vs find --old 'D:\data\cfg' --root "$ROOT" run.sh)
assert_eq "a PATH argument restricts the file set" "1" "$(row_count "$OUT")"

# --- bare drive letter ---------------------------------------------------------
FX=$(new_fixture bare)
put "$FX" notes.md 'Drive D: holds the data.' 'ID: 42' 'See https://example.com/d/page'
put "$FX" conf.yaml 'd: true'
put "$FX" run.sh 'cd /d/'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:' --root "$ROOT")
assert_contains "bare D: found as a word" "$OUT" $'setup\tnotes.md\t1\t7\texact'
assert_not_contains "bare D: not inside ID:" "$OUT" $'notes.md\t2'
assert_not_contains "bare D: not in a URL /d/ segment" "$OUT" $'notes.md\t3'
assert_not_contains "bare D: creates no MSYS form" "$OUT" "run.sh"
assert_contains "YAML d: key only as a case row" "$OUT" $'setup\tconf.yaml\t1\t1\tcase\tdefault'
assert_eq "bare D: yields exactly two sites" "2" "$(row_count "$OUT")"

# --- classes -------------------------------------------------------------------
FX=$(new_fixture classes)
put "$FX" README.md 'v Q:\vol\one'
put "$FX" CHANGELOG.md 'v Q:\vol\one'
put "$FX" PLAN.md 'v Q:\vol\one'
put "$FX" docs/specs/x.md 'v Q:\vol\one'
put "$FX" tests/x.sh 'v Q:\vol\one'
put "$FX" lib/run.test.sh 'v Q:\vol\one'
put "$FX" gen/out.txt '# DO NOT EDIT: built by a tool' 'v Q:\vol\one'
put "$FX" latest/notes.md 'v Q:\vol\one'
put "$FX" docs/changelog.md 'v Q:\vol\one'
printf 'v Q:\\vol\\one\000\001binary\n' >"$FX/blob.bin"
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(slashes "$(vs find --old 'Q:\vol\one' --root "$ROOT")")
assert_contains "README is setup by default" "$OUT" $'setup\tREADME.md\t1\t3\texact\tdefault'
assert_contains "CHANGELOG is a record" "$OUT" $'record\tCHANGELOG.md\t1\t3\texact\tname:CHANGELOG*'
assert_contains "PLAN.md is a contract" "$OUT" $'contract\tPLAN.md\t1\t3\texact\tname:PLAN.md'
assert_contains "docs/specs is a contract" "$OUT" $'contract\tdocs/specs/x.md\t1\t3\texact\tsegment:specs'
assert_contains "tests/ is a fixture" "$OUT" $'fixture\ttests/x.sh\t1\t3\texact\tsegment:tests'
assert_contains "*.test.sh is a fixture" "$OUT" $'fixture\tlib/run.test.sh\t1\t3\texact\tname:*.test.*'
assert_contains "DO NOT EDIT header is generated" "$OUT" $'generated\tgen/out.txt\t2\t3\texact\tmarker:do not edit'
assert_contains "latest/notes.md stays setup" "$OUT" $'setup\tlatest/notes.md\t1\t3\texact\tdefault'
assert_contains "a lowercase changelog is a record" "$OUT" $'record\tdocs/changelog.md\t1\t3\texact\tname:CHANGELOG*'
assert_not_contains "binary file is skipped" "$OUT" "blob.bin"

SUM=$(vs find --old 'Q:\vol\one' --root "$ROOT" --format summary)
assert_contains "summary counts skipped binaries" "$SUM" "skipped-binary: 1"
assert_contains "summary per-file count" "$SUM" $'file\tREADME.md\t1'
assert_contains "summary setup count" "$SUM" $'class\tsetup\t2'
assert_contains "summary record count" "$SUM" $'class\trecord\t2'
assert_contains "summary contract count" "$SUM" $'class\tcontract\t2'
assert_contains "summary fixture count" "$SUM" $'class\tfixture\t2'
assert_contains "summary generated count" "$SUM" $'class\tgenerated\t1'
assert_contains "summary total" "$SUM" "sites: 9"

# --- exits ---------------------------------------------------------------------
rc=0
vs find --old 'Z:\absent' --root "$ROOT" >/dev/null || rc=$?
assert_exit "no match exits 1" 1 "$rc"
NOGIT="$TEST_TMPDIR/nogit"
mkdir -p "$NOGIT"
rc=0
ERR=$(vs find --old 'D:' --root "$(host_path "$NOGIT")" 2>&1 >/dev/null) || rc=$?
assert_exit "non-git root exits 2" 2 "$rc"
assert_contains "non-git root names the problem" "$ERR" "not a git"
rc=0
vs find >/dev/null 2>&1 || rc=$?
assert_exit "missing --old exits 2" 2 "$rc"

# --- apply: backslash value, no control bytes --------------------------------
FX=$(new_fixture apply)
put "$FX" README.md 'Data lives in D:\data\cfg for now.' 'Second copy D:\data\cfg stays.'
put "$FX" app.json '{"dir": "D:\\data\\cfg"}'
put "$FX" setup.sh 'DATA=D:/data/cfg'
stage "$FX"
ROOT=$(host_path "$FX")
rc=0
OUT=$(vs apply --old 'D:\data\cfg' --new 'E:\data\cfg\current' --root "$ROOT" README.md:1 app.json:1 setup.sh:1) || rc=$?
assert_exit "apply exits 0" 0 "$rc"
assert_eq "one printed row per site" "3" "$(row_count "$OUT")"
assert_eq "backslash value written literally" 'Data lives in E:\data\cfg\current for now.' "$(sed -n 1p "$FX/README.md")"
assert_eq "apply writes no control bytes" "0" "$(control_bytes "$FX/README.md")"
assert_eq "unlisted matching line keeps the old value" 'Second copy D:\data\cfg stays.' "$(sed -n 2p "$FX/README.md")"
assert_eq "JSON gets the doubled-backslash form" '{"dir": "E:\\data\\cfg\\current"}' "$(cat "$FX/app.json")"
assert_eq "shell file gets the slash form" 'DATA=E:/data/cfg/current' "$(cat "$FX/setup.sh")"

# --- apply: CRLF and BOM -------------------------------------------------------
FX=$(new_fixture crlf)
{
  printf '\xef\xbb\xbf'
  printf '%s\r\n' 'root D:\data\cfg' 'plain line'
} >"$FX/win.txt"
{
  printf '\xef\xbb\xbf'
  printf '%s\r\n' 'root E:\data\cfg\current' 'plain line'
} >"$TEST_TMPDIR/win.expected"
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:\data\cfg' --root "$ROOT")
assert_contains "BOM does not shift the column" "$OUT" $'win.txt\t1\t6\texact'
assert_not_contains "row text carries no CR" "$OUT" $'\r'
rc=0
vs apply --old 'D:\data\cfg' --new 'E:\data\cfg\current' --root "$ROOT" win.txt:1 >/dev/null || rc=$?
assert_exit "apply on CRLF+BOM exits 0" 0 "$rc"
if cmp -s "$FX/win.txt" "$TEST_TMPDIR/win.expected"; then
  pass "apply keeps CRLF and the UTF-8 BOM"
else
  fail "apply keeps CRLF and the UTF-8 BOM" "bytes differ from expected"
fi

# --- apply: refusals -----------------------------------------------------------
FX=$(new_fixture refuse)
put "$FX" README.md 'v Q:\vol\one'
put "$FX" CHANGELOG.md 'v Q:\vol\one'
put "$FX" PLAN.md 'v Q:\vol\one'
put "$FX" gen/out.txt '// @generated' 'v Q:\vol\one'
put "$FX" tests/x.sh 'v Q:\vol\one'
stage "$FX"
ROOT=$(host_path "$FX")
BEFORE=$(git -C "$FX" diff --no-ext-diff)

rc=0
ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" README.md:2 2>&1 >/dev/null) || rc=$?
assert_exit "stale line anchor exits 3" 3 "$rc"
assert_contains "stale anchor names the site" "$ERR" "README.md:2"
rc=0
ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" CHANGELOG.md:1 2>&1 >/dev/null) || rc=$?
assert_exit "record site refused" 3 "$rc"
assert_contains "record refusal names the site" "$ERR" "CHANGELOG.md:1"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" PLAN.md:1 >/dev/null 2>&1 || rc=$?
assert_exit "contract site refused" 3 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" gen/out.txt:2 >/dev/null 2>&1 || rc=$?
assert_exit "generated site refused" 3 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" tests/x.sh:1 >/dev/null 2>&1 || rc=$?
assert_exit "fixture site refused without --allow-fixture" 3 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" README.md:1 PLAN.md:1 >/dev/null 2>&1 || rc=$?
assert_exit "one refused site refuses the whole run" 3 "$rc"
assert_eq "refusals write nothing" "$BEFORE" "$(git -C "$FX" diff --no-ext-diff)"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" README.md >/dev/null 2>&1 || rc=$?
assert_exit "a site without :line exits 2" 2 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new $'Q:\\vol\x01' --root "$ROOT" README.md:1 >/dev/null 2>&1 || rc=$?
assert_exit "a write that changes the control-byte count is refused" 3 "$rc"
assert_eq "control-byte refusal writes nothing" "$BEFORE" "$(git -C "$FX" diff --no-ext-diff)"

rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" --allow-fixture tests/x.sh:1 >/dev/null || rc=$?
assert_exit "fixture site applied with --allow-fixture" 0 "$rc"
assert_eq "fixture file changed" 'v Q:\vol\two' "$(cat "$FX/tests/x.sh")"

echo
if [[ "$FAILED" -gt 0 ]]; then
  echo "value-sites.test.sh: $FAILED of $CASE_NUM FAILED" >&2
  exit 1
fi
echo "value-sites.test.sh: all $CASE_NUM passed"
