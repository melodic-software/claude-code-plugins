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
SKIPPED=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
# skip LABEL REASON: a case this host cannot exercise; counted apart from CASE_NUM.
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP: %s\n  reason: %s\n' "$1" "$2"
}

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
# site_rows OUT: find output without its skip rows; site_count counts them.
site_rows() { printf '%s\n' "$1" | grep -v $'^skip\t' || true; }
site_count() { row_count "$(site_rows "$1")"; }
# anchor TEXT [PREV] [NEXT]: the anchor value-sites.py gives a line with this
# text between these neighbours (empty for a first or last line).
anchor() { printf '%s\n%s\n%s' "${2:-}" "$1" "${3:-}" | python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:12])'; }
# sites OUT PATH:LINE...: the apply SITE of every find row on each listed line.
sites() {
  local out="$1" pl
  shift
  for pl in "$@"; do
    printf '%s\n' "$out" | awk -F'\t' -v p="${pl%:*}" -v l="${pl##*:}" \
      '$1 != "skip" && $2 == p && $3 == l { print $2 ":" $3 ":" $4 ":" $7 }'
  done
}
# control_bytes FILE: count bytes below 0x20 other than tab, LF, CR.
control_bytes() { LC_ALL=C tr -d '\t\n\r\040-\377' <"$1" | wc -c | tr -d ' '; }
# untracked FX: untracked paths git sees (a temp file left behind shows here).
untracked() { git -C "$1" status --porcelain --untracked-files=all | grep '^??' || true; }

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
assert_eq "exactly five sites" "5" "$(site_count "$OUT")"
WSL_ROW=$(printf '%s\n' "$OUT" | grep -F $'\twsl.sh\t')
assert_eq "row carries the line's anchor, then the line without its newline" \
  $'setup\twsl.sh\t1\t4\twsl\tdefault\t'"$(anchor 'cd /mnt/d/data/cfg')"$'\tcd /mnt/d/data/cfg' "$WSL_ROW"

# find is read-only
BEFORE=$(git -C "$FX" status --porcelain)
vs find --old 'D:\data\cfg' --root "$ROOT" >/dev/null
vs find --old 'D:\data\cfg' --root "$ROOT" --format summary >/dev/null
AFTER=$(git -C "$FX" status --porcelain)
assert_eq "find leaves the tree unchanged" "$BEFORE" "$AFTER"

# PATH restriction
OUT=$(vs find --old 'D:\data\cfg' --root "$ROOT" run.sh)
assert_eq "a PATH argument restricts the file set" "1" "$(site_count "$OUT")"

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
assert_contains "YAML d: key only as a case row" "$OUT" $'setup\tconf.yaml\t1\t1\tcase:exact\tdefault'
assert_eq "bare D: yields exactly two sites" "2" "$(site_count "$OUT")"

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
assert_contains "F3: binary file is a skip row" "$OUT" $'skip\tblob.bin\tbinary'
assert_not_contains "binary file has no site row" "$(site_rows "$OUT")" "blob.bin"

SUM=$(vs find --old 'Q:\vol\one' --root "$ROOT" --format summary)
assert_contains "F3: summary counts skipped files" "$SUM" "skipped: 1"
assert_contains "summary per-file count" "$SUM" $'file\tREADME.md\t1'
assert_contains "summary setup count" "$SUM" $'class\tsetup\t2'
assert_contains "summary record count" "$SUM" $'class\trecord\t2'
assert_contains "summary contract count" "$SUM" $'class\tcontract\t2'
assert_contains "summary fixture count" "$SUM" $'class\tfixture\t2'
assert_contains "summary generated count" "$SUM" $'class\tgenerated\t1'
assert_contains "summary total" "$SUM" "sites: 9"

# --- filename rules ignore case --------------------------------------------------
FX=$(new_fixture casenames)
put "$FX" plan.md 'v Q:\vol\one'
put "$FX" Tests/x.sh 'v Q:\vol\one'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(slashes "$(vs find --old 'Q:\vol\one' --root "$ROOT")")
assert_contains "plan.md is a contract" "$OUT" $'contract\tplan.md\t1\t3\texact\tname:PLAN.md'
assert_contains "Tests/ is a fixture" "$OUT" $'fixture\tTests/x.sh\t1\t3\texact\tsegment:tests'

# --- overlapping forms -------------------------------------------------------------
FX=$(new_fixture overlap)
put "$FX" app.json '{"dir": "D:\\data"}'
put "$FX" cfg.json '{"dir": "cfg\\"}'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:\data' --root "$ROOT")
assert_eq "doubled spelling yields one row" \
  $'setup\tapp.json\t1\t10\tdoubled\tdefault\t'"$(anchor '{"dir": "D:\\data"}')"$'\t{"dir": "D:\\\\data"}' "$OUT"
OUT=$(vs find --old $'cfg\\' --root "$ROOT")
assert_eq "exact and doubled overlap at one start: one row, the longer form" \
  $'setup\tcfg.json\t1\t10\tdoubled\tdefault\t'"$(anchor '{"dir": "cfg\\"}')"$'\t{"dir": "cfg\\\\"}' "$OUT"

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
rc=0
vs --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

# --- apply: backslash value, no control bytes --------------------------------
FX=$(new_fixture apply)
put "$FX" README.md 'Data lives in D:\data\cfg for now.' 'Second copy D:\data\cfg stays.'
put "$FX" app.json '{"dir": "D:\\data\\cfg"}'
put "$FX" setup.sh 'DATA=D:/data/cfg'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:\data\cfg' --root "$ROOT")
mapfile -t S < <(sites "$OUT" README.md:1 app.json:1 setup.sh:1)
rc=0
OUT=$(vs apply --old 'D:\data\cfg' --new 'E:\data\cfg\current' --root "$ROOT" "${S[@]}") || rc=$?
assert_exit "apply exits 0" 0 "$rc"
assert_eq "one printed row per site" "3" "$(row_count "$OUT")"
assert_eq "backslash value written literally" 'Data lives in E:\data\cfg\current for now.' "$(sed -n 1p "$FX/README.md")"
assert_eq "apply writes no control bytes" "0" "$(control_bytes "$FX/README.md")"
assert_eq "unlisted matching line keeps the old value" 'Second copy D:\data\cfg stays.' "$(sed -n 2p "$FX/README.md")"
assert_eq "JSON gets the doubled-backslash form" '{"dir": "E:\\data\\cfg\\current"}' "$(cat "$FX/app.json")"
assert_eq "shell file gets the slash form" 'DATA=E:/data/cfg/current' "$(cat "$FX/setup.sh")"
assert_eq "F5: a successful apply leaves no temp file" "" "$(untracked "$FX")"

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
assert_contains "F1: the anchor hashes the line without BOM or CR" "$OUT" $'\t'"$(anchor 'root D:\data\cfg' '' 'plain line')"$'\t'
mapfile -t S < <(sites "$OUT" win.txt:1)
rc=0
vs apply --old 'D:\data\cfg' --new 'E:\data\cfg\current' --root "$ROOT" "${S[@]}" >/dev/null || rc=$?
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
OUT=$(vs find --old 'Q:\vol\one' --root "$ROOT")
A1=$(anchor 'v Q:\vol\one')

rc=0
ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "README.md:2:3:$A1" 2>&1 >/dev/null) || rc=$?
assert_exit "stale line anchor exits 3" 3 "$rc"
assert_contains "stale anchor names the site" "$ERR" "README.md:2"
rc=0
ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "$(sites "$OUT" CHANGELOG.md:1)" 2>&1 >/dev/null) || rc=$?
assert_exit "record site refused" 3 "$rc"
assert_contains "record refusal names the site" "$ERR" "CHANGELOG.md:1"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "$(sites "$OUT" PLAN.md:1)" >/dev/null 2>&1 || rc=$?
assert_exit "contract site refused" 3 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "$(sites "$OUT" gen/out.txt:2)" >/dev/null 2>&1 || rc=$?
assert_exit "generated site refused" 3 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "$(sites "$OUT" tests/x.sh:1)" >/dev/null 2>&1 || rc=$?
assert_exit "fixture site refused without --allow-fixture" 3 "$rc"
mapfile -t S < <(sites "$OUT" README.md:1 PLAN.md:1)
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "${S[@]}" >/dev/null 2>&1 || rc=$?
assert_exit "one refused site refuses the whole run" 3 "$rc"
assert_eq "refusals write nothing" "$BEFORE" "$(git -C "$FX" diff --no-ext-diff)"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" README.md >/dev/null 2>&1 || rc=$?
assert_exit "a site without :line exits 2" 2 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" README.md:1 >/dev/null 2>&1 || rc=$?
assert_exit "F1: a bare path:line site exits 2" 2 "$rc"
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" README.md:1:3:xyz >/dev/null 2>&1 || rc=$?
assert_exit "F1: a malformed anchor exits 2" 2 "$rc"
assert_eq "F1: usage errors write nothing" "$BEFORE" "$(git -C "$FX" diff --no-ext-diff)"
rc=0
vs apply --old 'Q:\vol\one' --new $'Q:\\vol\x01' --root "$ROOT" "$(sites "$OUT" README.md:1)" >/dev/null 2>&1 || rc=$?
assert_exit "a write that changes the control-byte count is refused" 3 "$rc"
assert_eq "control-byte refusal writes nothing" "$BEFORE" "$(git -C "$FX" diff --no-ext-diff)"

rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" --allow-fixture "$(sites "$OUT" tests/x.sh:1)" >/dev/null || rc=$?
assert_exit "fixture site applied with --allow-fixture" 0 "$rc"
assert_eq "fixture file changed" 'v Q:\vol\two' "$(cat "$FX/tests/x.sh")"

# --- apply: every form keeps its spelling ------------------------------------------
FX=$(new_fixture forms-apply)
put "$FX" README.md 'Data lives in D:\data\cfg for now.'
put "$FX" run.sh 'cd /d/data/cfg'
put "$FX" wsl.sh 'cd /mnt/d/data/cfg'
put "$FX" case.json '{"dir": "d:\\data\\cfg"}'
put "$FX" case.sh 'cd /D/data/cfg'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:\data\cfg' --root "$ROOT")
assert_contains "case-folded doubled match is tagged case:doubled" "$OUT" $'case.json\t1\t10\tcase:doubled'
assert_contains "case-folded MSYS match is tagged case:msys" "$OUT" $'case.sh\t1\t4\tcase:msys'
rc=0
ERR=$(vs apply --old 'D:\data\cfg' --new 'E:\data\new' --root "$ROOT" "README.md:99:15:$(anchor 'Data lives in D:\data\cfg for now.')" 2>&1 >/dev/null) || rc=$?
assert_exit "a line past the end of the file is refused" 3 "$rc"
assert_contains "past-EOF refusal names the site" "$ERR" "README.md:99"
mapfile -t S < <(sites "$OUT" run.sh:1 wsl.sh:1 case.json:1 case.sh:1)
rc=0
vs apply --old 'D:\data\cfg' --new 'E:\data\new' --root "$ROOT" "${S[@]}" >/dev/null || rc=$?
assert_exit "apply on msys, wsl and case sites exits 0" 0 "$rc"
assert_eq "MSYS site gets the MSYS spelling" 'cd /e/data/new' "$(cat "$FX/run.sh")"
assert_eq "WSL site gets the WSL spelling" 'cd /mnt/e/data/new' "$(cat "$FX/wsl.sh")"
assert_eq "case:doubled site gets doubled backslashes" '{"dir": "E:\\data\\new"}' "$(cat "$FX/case.json")"
assert_eq "case:msys site gets the MSYS spelling" 'cd /e/data/new' "$(cat "$FX/case.sh")"

# --- apply: sites are confined to tracked files under the root ---------------------
FX=$(new_fixture confine)
put "$FX" README.md 'v Q:\vol\one'
stage "$FX"
put "$FX" notes.md 'v Q:\vol\one'
printf '%s\n' 'v Q:\vol\one' >"$TEST_TMPDIR/outside.txt"
ROOT=$(host_path "$FX")
A1=$(anchor 'v Q:\vol\one')
rc=0
ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "README.md:1:3:$A1" "../outside.txt:1:3:$A1" 2>&1 >/dev/null) || rc=$?
assert_exit "a site outside the root is refused" 3 "$rc"
assert_contains "outside refusal names the site" "$ERR" "outside.txt"
assert_eq "the outside file is unchanged" 'v Q:\vol\one' "$(cat "$TEST_TMPDIR/outside.txt")"
assert_eq "confinement refusal writes nothing in the root" 'v Q:\vol\one' "$(cat "$FX/README.md")"
rc=0
ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "README.md:1:3:$A1" "notes.md:1:3:$A1" 2>&1 >/dev/null) || rc=$?
assert_exit "an untracked file inside the root is refused" 3 "$rc"
assert_contains "untracked refusal names the site" "$ERR" "notes.md:1"
assert_eq "the untracked file is unchanged" 'v Q:\vol\one' "$(cat "$FX/notes.md")"
assert_eq "untracked refusal writes nothing else" 'v Q:\vol\one' "$(cat "$FX/README.md")"

# --- apply: one file named two ways is one write -----------------------------------
FX=$(new_fixture dedup)
put "$FX" dup.md 'one Q:\vol\one' 'two Q:\vol\one'
put "$FX" docs/keep.md 'kept'
put "$FX" A.md 'one Q:\vol\one' 'two Q:\vol\one'
stage "$FX"
ROOT=$(host_path "$FX")
L1="1:5:$(anchor 'one Q:\vol\one' '' 'two Q:\vol\one')"
L2="2:5:$(anchor 'two Q:\vol\one' 'one Q:\vol\one')"
rc=0
OUT=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "dup.md:$L1" "docs/../dup.md:$L2") || rc=$?
assert_exit "apply with two spellings of one file exits 0" 0 "$rc"
assert_eq "both edits land in one write" $'one Q:\\vol\\two\ntwo Q:\\vol\\two' "$(cat "$FX/dup.md")"
if [[ -e "$FX/a.md" ]]; then
  rc=0
  vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "A.md:$L1" "a.md:$L2" >/dev/null || rc=$?
  assert_exit "apply with two casings of one file exits 0" 0 "$rc"
  assert_eq "both casings' edits land in one write" $'one Q:\\vol\\two\ntwo Q:\\vol\\two' "$(cat "$FX/A.md")"
else
  skip "apply with two casings of one file" "case-sensitive filesystem"
fi

# --- a dot scope means the whole repository -----------------------------------------
FX=$(new_fixture dotscope)
put "$FX" README.md 'v Q:\vol\one'
put "$FX" docs/guide.md 'v Q:\vol\one'
stage "$FX"
ROOT=$(host_path "$FX")
assert_eq "scope . finds every site" "2" "$(site_count "$(vs find --old 'Q:\vol\one' --root "$ROOT" .)")"
assert_eq "scope ./ finds every site" "2" "$(site_count "$(vs find --old 'Q:\vol\one' --root "$ROOT" ./)")"

# --- protected surfaces: CI, agent settings, hooks, lint configs, migrations ---------
FX=$(new_fixture protected)
put "$FX" .github/workflows/ci.yml 'pin: Q:\vol\one'
put "$FX" .claude/settings.json '{"dir": "Q:\\vol\\one"}'
put "$FX" .githooks/pre.sh 'v Q:\vol\one'
put "$FX" .gitlab-ci.yml 'v: Q:\vol\one'
put "$FX" Jenkinsfile 'v Q:\vol\one'
put "$FX" .circleci/config.yml 'v: Q:\vol\one'
put "$FX" plugins/x/hooks/hooks.json '{"dir": "Q:\\vol\\one"}'
put "$FX" src/hooks/useConfig.ts 'const DIR = "Q:\vol\one"'
put "$FX" ruff.toml 'v = "Q:\vol\one"'
put "$FX" .pre-commit-config.yaml 'v: Q:\vol\one'
put "$FX" db/migrations/001.sql '-- Q:\vol\one'
put "$FX" README.md 'v Q:\vol\one'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'Q:\vol\one' --root "$ROOT")
assert_contains "workflow is protected" "$OUT" $'protected\t.github/workflows/ci.yml\t1\t6\texact\tsegment:.github'
assert_contains "agent settings are protected" "$OUT" $'protected\t.claude/settings.json'
assert_contains "git hook script is protected" "$OUT" $'protected\t.githooks/pre.sh\t1\t3\texact\tsegment:.githooks'
assert_contains "GitLab CI config is protected" "$OUT" $'protected\t.gitlab-ci.yml\t1\t4\texact\tname:.gitlab-ci.yml'
assert_contains "Jenkinsfile is protected" "$OUT" $'protected\tJenkinsfile\t1\t3\texact\tname:jenkinsfile'
assert_contains "CircleCI config is protected" "$OUT" $'protected\t.circleci/config.yml\t1\t4\texact\tsegment:.circleci'
assert_contains "hook manifest is protected" "$OUT" $'protected\tplugins/x/hooks/hooks.json\t1\t10\tdoubled\tname:hooks.json'
assert_contains "an app's own hooks/ folder stays setup" "$OUT" $'setup\tsrc/hooks/useConfig.ts\t1\t14\texact\tdefault'
assert_contains "lint config is protected" "$OUT" $'protected\truff.toml\t1\t6\texact\tname:ruff.toml'
assert_contains "pre-commit config is protected" "$OUT" $'protected\t.pre-commit-config.yaml'
assert_contains "migration is protected" "$OUT" $'protected\tdb/migrations/001.sql\t1\t4\texact\tsegment:migrations'
assert_contains "README stays setup" "$OUT" $'setup\tREADME.md'
assert_contains "summary counts protected" "$(vs find --old 'Q:\vol\one' --root "$ROOT" --format summary)" $'class\tprotected\t10'
mapfile -t S < <(sites "$OUT" README.md:1 .github/workflows/ci.yml:1)
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "${S[@]}" >/dev/null 2>&1 || rc=$?
assert_exit "apply refuses a protected site" 3 "$rc"
assert_eq "protected refusal writes nothing" 'v Q:\vol\one' "$(cat "$FX/README.md")"

# --- a target that cannot be written stops the run before any write -------------------
if [[ "$(id -u 2>/dev/null)" != "0" ]]; then
  FX=$(new_fixture readonly)
  put "$FX" a.md 'v Q:\vol\one'
  put "$FX" b.md 'v Q:\vol\one'
  stage "$FX"
  chmod a-w "$FX/b.md"
  ROOT=$(host_path "$FX")
  A1=$(anchor 'v Q:\vol\one')
  rc=0
  vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "a.md:1:3:$A1" "b.md:1:3:$A1" >/dev/null 2>&1 || rc=$?
  chmod u+w "$FX/b.md"
  assert_exit "an unwritable target is refused" 3 "$rc"
  assert_eq "no earlier target is written" 'v Q:\vol\one' "$(cat "$FX/a.md")"
else
  skip "an unwritable target is refused" "running as root"
fi

# --- F1: a site is path:line:col:anchor, checked at write time -----------------------
FX=$(new_fixture swap)
put "$FX" README.md 'Install to D:/data' 'We once used D:/data (keep)'
put "$FX" same.md 'new: D:/data' 'old: D:/data (keep)'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:/data' --root "$ROOT")
mapfile -t S < <(sites "$OUT" README.md:1)
assert_eq "F1: line 1 carries one site" "1" "${#S[@]}"
put "$FX" README.md 'We once used D:/data (keep)' 'Install to D:/data'
rc=0
ERR=$(vs apply --old 'D:/data' --new 'E:/work' --root "$ROOT" "${S[@]}" 2>&1 >/dev/null) || rc=$?
assert_exit "F1: a confirmed site whose lines swapped is refused" 3 "$rc"
assert_eq "F1: neither swapped line changes" $'We once used D:/data (keep)\nInstall to D:/data' "$(cat "$FX/README.md")"
mapfile -t S < <(sites "$OUT" same.md:1)
put "$FX" same.md 'old: D:/data (keep)' 'new: D:/data'
rc=0
ERR=$(vs apply --old 'D:/data' --new 'E:/work' --root "$ROOT" "${S[@]}" 2>&1 >/dev/null) || rc=$?
assert_exit "F1: same column, different line text: the anchor refuses" 3 "$rc"
assert_contains "F1: the refusal names the anchor" "$ERR" "anchor"
assert_eq "F1: the same-column swap writes nothing" $'old: D:/data (keep)\nnew: D:/data' "$(cat "$FX/same.md")"
rc=0
ERR=$(vs apply --old 'D:/data' --new 'E:/work' --root "$ROOT" "same.md:2:3:$(anchor 'new: D:/data' 'old: D:/data (keep)')" 2>&1 >/dev/null) || rc=$?
assert_exit "F1: the right anchor at a column with no match is refused" 3 "$rc"
assert_contains "F1: the column refusal names the column" "$ERR" "col 3"

FX=$(new_fixture mixed)
put "$FX" README.md 'D:/data to D:/data-archive and D:/data.old'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:/data' --root "$ROOT")
mapfile -t S < <(sites "$OUT" README.md:1)
assert_eq "F1: three matches on one line are three sites" "3" "${#S[@]}"
rc=0
OUT=$(vs apply --old 'D:/data' --new 'E:/work' --root "$ROOT" "${S[0]}") || rc=$?
assert_exit "F1: applying the first column exits 0" 0 "$rc"
assert_eq "F1: only the confirmed column changes" 'E:/work to D:/data-archive and D:/data.old' "$(cat "$FX/README.md")"
assert_eq "F1: one applied row for one site" "1" "$(row_count "$OUT")"

# --- F2: classification additions and default-deny for unknown kinds -----------------
FX=$(new_fixture classes2)
PROT=(azure-pipelines.yaml .drone.yml AppVeyor.yml .woodpecker.yml cloudbuild.yaml
  .azure-pipelines/build.yml .gitlab/ci/build.yml
  .prettierrc .prettierrc.json prettier.config.js .flake8 .pylintrc .stylelintrc.json biome.json
  .yamllint .rubocop.yml lefthook.yml .lintstagedrc mypy.ini
  src/main/resources/db/migration/V1__init.sql db/migrate/2020_create.rb alembic/versions/abc_init.py)
for p in "${PROT[@]}"; do put "$FX" "$p" 'v Q:\vol\one'; done
for p in CHANGES.md NEWS.md changelog.d/123.feature.md LICENSE notes.xyz tests/data.xyz Makefile Dockerfile .env docs/setup.md; do
  put "$FX" "$p" 'v Q:\vol\one'
done
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(slashes "$(vs find --old 'Q:\vol\one' --root "$ROOT")")
for p in "${PROT[@]}"; do
  assert_contains "F2: $p is protected" "$OUT" $'protected\t'"$p"$'\t'
done
assert_contains "F2: CI name compared case-insensitively" "$OUT" $'protected\tAppVeyor.yml\t1\t3\texact\tname:appveyor.yml'
assert_contains "F2: .gitlab segment reason" "$OUT" $'\t.gitlab/ci/build.yml\t1\t3\texact\tsegment:.gitlab'
assert_contains "F2: db/migration segment reason" "$OUT" $'\tsegment:migration\t'
assert_contains "F2: db/migrate segment reason" "$OUT" $'\tsegment:migrate\t'
assert_contains "F2: alembic segment reason" "$OUT" $'\tsegment:alembic\t'
assert_contains "F2: CHANGES is a record" "$OUT" $'record\tCHANGES.md\t1\t3\texact\tname:CHANGES*'
assert_contains "F2: NEWS is a record" "$OUT" $'record\tNEWS.md\t1\t3\texact\tname:NEWS*'
assert_contains "F2: changelog.d is a record" "$OUT" $'record\tchangelog.d/123.feature.md\t1\t3\texact\tsegment:changelog.d'
assert_contains "F2: an extensionless unknown kind is unknown" "$OUT" $'unknown\tLICENSE\t1\t3\texact\tdefault:unknown-kind'
assert_contains "F2: an unknown extension is unknown" "$OUT" $'unknown\tnotes.xyz\t1\t3\texact\tdefault:unknown-kind'
assert_contains "F2: a fixture rule fires before unknown" "$OUT" $'fixture\ttests/data.xyz'
assert_contains "F2: Makefile is setup" "$OUT" $'setup\tMakefile\t'
assert_contains "F2: Dockerfile is setup" "$OUT" $'setup\tDockerfile\t'
assert_contains "F2: .env is setup" "$OUT" $'setup\t.env\t'
assert_contains "F2: a markdown doc is setup" "$OUT" $'setup\tdocs/setup.md\t'
assert_contains "F2: summary counts unknown" "$(vs find --old 'Q:\vol\one' --root "$ROOT" --format summary)" $'class\tunknown\t2'
mapfile -t S < <(sites "$OUT" docs/setup.md:1 notes.xyz:1)
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "${S[@]}" >/dev/null 2>&1 || rc=$?
assert_exit "F2: apply refuses an unknown-kind site" 3 "$rc"
assert_eq "F2: the unknown refusal writes nothing" 'v Q:\vol\one' "$(cat "$FX/docs/setup.md")"
mapfile -t S < <(sites "$OUT" .gitlab/ci/build.yml:1 db/migrate/2020_create.rb:1 .prettierrc:1)
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "${S[@]}" >/dev/null 2>&1 || rc=$?
assert_exit "F2: apply refuses the added protected kinds" 3 "$rc"

# --- F3: binary and UTF-16/UTF-32 files are skip rows and never written --------------
FX=$(new_fixture unreadable)
put "$FX" README.md 'v Q:\vol\one'
printf '\xff\xfe%s\n' 'v Q:\vol\one' >"$FX/u16.md"
printf '\xff\xfe\x00\x00%s\n' 'v Q:\vol\one' >"$FX/u32.md"
printf 'v Q:\\vol\\one\n\000\001' >"$FX/blob.md"
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'Q:\vol\one' --root "$ROOT")
assert_contains "F3: a UTF-16 BOM file is a skip row" "$OUT" $'skip\tu16.md\tutf-16'
assert_contains "F3: a UTF-32 BOM file is a skip row" "$OUT" $'skip\tu32.md\tutf-32'
assert_contains "F3: a NUL-bearing file is a binary skip row" "$OUT" $'skip\tblob.md\tbinary'
assert_eq "F3: skip rows are not sites" "1" "$(site_count "$OUT")"
assert_contains "F3: summary counts every skip" "$(vs find --old 'Q:\vol\one' --root "$ROOT" --format summary)" "skipped: 3"
A1=$(anchor 'v Q:\vol\one')
for f in u16.md blob.md; do
  BEFORE_BYTES=$(od -An -tx1 "$FX/$f")
  rc=0
  ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "$f:1:3:$A1" 2>&1 >/dev/null) || rc=$?
  assert_exit "F3: apply refuses $f" 3 "$rc"
  assert_eq "F3: $f is unchanged" "$BEFORE_BYTES" "$(od -An -tx1 "$FX/$f")"
done

# --- F4: a match does not end before ~digit (8.3 short names) -------------------------
FX=$(new_fixture tilde)
put "$FX" README.md 'short D:/data~1 name' 'plain D:/data here'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:/data' --root "$ROOT")
assert_not_contains "F4: D:/data~1 is a different directory" "$OUT" $'README.md\t1\t'
assert_eq "F4: only the plain line is a site" "1" "$(site_count "$OUT")"

# --- F5: hardlinks, resolved paths, and atomic writes ---------------------------------
FX=$(new_fixture hardlink)
put "$FX" linked.md 'v Q:\vol\one'
stage "$FX"
ROOT=$(host_path "$FX")
if ln "$FX/linked.md" "$TEST_TMPDIR/hardlink-outside.md" 2>/dev/null &&
  [[ "$(python3 -c 'import os, sys; print(os.stat(sys.argv[1]).st_nlink)' "$(host_path "$FX/linked.md")")" == "2" ]]; then
  rc=0
  ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "linked.md:1:3:$(anchor 'v Q:\vol\one')" 2>&1 >/dev/null) || rc=$?
  assert_exit "F5: a hardlinked target is refused" 3 "$rc"
  assert_contains "F5: the refusal names the hardlink" "$ERR" "hardlink"
  assert_eq "F5: the linked file outside the root is unchanged" 'v Q:\vol\one' "$(cat "$TEST_TMPDIR/hardlink-outside.md")"
else
  skip "F5: a hardlinked target is refused" "ln cannot make a hard link here"
fi

FX=$(new_fixture outside)
put "$FX" README.md 'v Q:\vol\one'
printf '%s\n' 'v Q:\vol\one' >"$TEST_TMPDIR/outside-target.md"
if MSYS=winsymlinks:nativestrict ln -s "$TEST_TMPDIR/outside-target.md" "$FX/out.md" 2>/dev/null && [[ -L "$FX/out.md" ]]; then
  stage "$FX"
  if [[ "$(git -C "$FX" ls-files -s out.md)" == 120000* ]]; then
    OUT=$(vs find --old 'Q:\vol\one' --root "$(host_path "$FX")")
    assert_contains "F5: a tracked path resolving outside the root is a skip row" "$OUT" $'skip\tout.md\toutside-root'
    assert_eq "F5: the outside path is not a site" "1" "$(site_count "$OUT")"
  else
    skip "F5: a tracked path resolving outside the root is a skip row" "git does not track symlinks here"
  fi
else
  skip "F5: a tracked path resolving outside the root is a skip row" "cannot create a symlink here"
fi

FX=$(new_fixture atomic)
put "$FX" a.md 'v Q:\vol\one'
put "$FX" locked/b.md 'v Q:\vol\one'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'Q:\vol\one' --root "$ROOT")
mapfile -t S < <(sites "$OUT" a.md:1 locked/b.md:1)
chmod a-w "$FX/locked"
if touch "$FX/locked/probe" 2>/dev/null; then
  rm -f "$FX/locked/probe"
  chmod u+w "$FX/locked"
  skip "F5: a write that fails midway restores every file" "a read-only directory still accepts new files here"
else
  rc=0
  ERR=$(vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "${S[@]}" 2>&1 >/dev/null) || rc=$?
  chmod u+w "$FX/locked"
  assert_exit "F5: a write that fails midway exits 2" 2 "$rc"
  assert_eq "F5: the file written first is restored" 'v Q:\vol\one' "$(cat "$FX/a.md")"
  assert_eq "F5: the failing file is unchanged" 'v Q:\vol\one' "$(cat "$FX/locked/b.md")"
  assert_eq "F5: no temp file is left after the failure" "" "$(untracked "$FX")"
fi

FX=$(new_fixture mode)
put "$FX" run.sh 'cd D:/data'
chmod +x "$FX/run.sh"
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:/data' --root "$ROOT")
rc=0
vs apply --old 'D:/data' --new 'E:/work' --root "$ROOT" "$(sites "$OUT" run.sh:1)" >/dev/null || rc=$?
assert_exit "F5: apply on an executable script exits 0" 0 "$rc"
assert_not_contains "F5: the atomic write keeps the file mode" "$(git -C "$FX" diff --summary)" "mode change"

# --- G1: tool default names, other forges, lock files, and records -------------------
FX=$(new_fixture classes3)
PROT3=(.appveyor.yml lefthook.yaml .lefthook.yml biome.jsonc .golangci.toml .golangci.json
  stylelint.config.js lint-staged.config.js .mypy.ini .woodpecker.yaml .woodpecker/build.yml
  .gitea/workflows/ci.yml .forgejo/workflows/ci.yml action.yml action.yaml
  db/changelog/db.changelog-master.yaml drizzle/0000_init.sql
  package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock Cargo.lock poetry.lock
  composer.lock Gemfile.lock go.sum packages.lock.json gradle.lockfile
  appveyor.yaml cloudbuild.yml cloudbuild.json .drone.yaml .pre-commit-config.yml
  .pre-commit-hooks.yaml .semaphore/semaphore.yml .tekton/run.yaml .cirrus.yml codecov.yml
  .vscode/settings.json .mcp.json)
REC3=(.changeset/brave-cats.md docs/adrs/0001-x.md ADR-0002-y.md release-notes/v1.md incidents/2024-01.md)
SETUP3=(sub/action.yml changelog/notes.md db/notes.md)
for p in "${PROT3[@]}" "${REC3[@]}" "${SETUP3[@]}"; do put "$FX" "$p" 'v Q:\vol\one'; done
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(slashes "$(vs find --old 'Q:\vol\one' --root "$ROOT")")
for p in "${PROT3[@]}"; do
  assert_contains "G1: $p is protected" "$OUT" $'protected\t'"$p"$'\t'
done
for p in "${REC3[@]}"; do
  assert_contains "G1: $p is a record" "$OUT" $'record\t'"$p"$'\t'
done
for p in "${SETUP3[@]}"; do
  assert_contains "G1: $p stays setup" "$OUT" $'setup\t'"$p"$'\t'
done
assert_contains "G1: dotted AppVeyor name reason" "$OUT" $'\t.appveyor.yml\t1\t3\texact\tname:*appveyor.yml\t'
assert_contains "G1: a root action is a root-name rule" "$OUT" $'\taction.yml\t1\t3\texact\troot-name:action.yml\t'
assert_contains "G1: Liquibase changelog is a two-segment rule" "$OUT" $'\tsegments:db/changelog\t'
assert_contains "G1: a lock file reason names its pattern" "$OUT" $'\tyarn.lock\t1\t3\texact\tname:*.lock\t'
mapfile -t S < <(sites "$OUT" .appveyor.yml:1 package-lock.json:1 docs/adrs/0001-x.md:1 db/notes.md:1)
rc=0
vs apply --old 'Q:\vol\one' --new 'Q:\vol\two' --root "$ROOT" "${S[@]}" >/dev/null 2>&1 || rc=$?
assert_exit "G1: apply refuses the added protected and record kinds" 3 "$rc"
assert_eq "G1: that refusal writes nothing" 'v Q:\vol\one' "$(cat "$FX/db/notes.md")"

# --- G1: the documented rule table equals the enforced rules -------------------------
DOC="$SCRIPT_DIR/../reference/change-mode.md"
DOC_RULES=$(tr -d '\r' <"$DOC" | awk -F'|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  /<!-- value-sites-rules:start -->/ { on = 1; next }
  /<!-- value-sites-rules:end -->/ { on = 0 }
  on && /^\|/ {
    c = trim($2); k = trim($3)
    if (c == "Class" || c ~ /^:?-+:?$/) next
    n = split($4, parts, ",")
    for (i = 1; i <= n; i++) { x = trim(parts[i]); gsub(/`/, "", x); print c "\t" k "\t" x }
  }' | LC_ALL=C sort -u)
rc=0
RULES_RAW=$(vs rules) || rc=$?
assert_exit "G1: rules exits 0" 0 "$rc"
RULES_OUT=$(printf '%s\n' "$RULES_RAW" | tr -d '\r' | LC_ALL=C sort -u)
assert_eq "G1: rules lists every class and kind in use" "" \
  "$(printf '%s\n' "$RULES_RAW" | awk -F'\t' 'NF != 3 || $3 == "" || $2 !~ /^(marker|segment|segments|name|root-name|extension-allow)$/' || true)"
if [[ -n "$RULES_OUT" && -n "$DOC_RULES" ]]; then
  pass "G1: both rule sets are non-empty"
else
  fail "G1: both rule sets are non-empty" "rules: $(row_count "$RULES_OUT") rows, doc: $(row_count "$DOC_RULES") rows"
fi
UNDOC=$(LC_ALL=C comm -23 <(printf '%s\n' "$RULES_OUT") <(printf '%s\n' "$DOC_RULES"))
UNENF=$(LC_ALL=C comm -13 <(printf '%s\n' "$RULES_OUT") <(printf '%s\n' "$DOC_RULES"))
assert_eq "G1: every enforced rule is in change-mode.md (first missing shown)" "" "${UNDOC%%$'\n'*}"
assert_eq "G1: every documented rule is enforced (first missing shown)" "" "${UNENF%%$'\n'*}"

# --- G2: the anchor covers the line and its two neighbours ---------------------------
FX=$(new_fixture moved)
put "$FX" README.md 'p D:/data' '> historical, keep:' 'p D:/data'
put "$FX" other.md 'o D:/data'
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:/data' --root "$ROOT")
mapfile -t S < <(sites "$OUT" README.md:1 other.md:1)
put "$FX" README.md 'p D:/data'
rc=0
ERR=$(vs apply --old 'D:/data' --new 'E:/work' --root "$ROOT" "${S[@]}" 2>&1 >/dev/null) || rc=$?
assert_exit "G2: an identical line moved into the confirmed number refuses the run" 3 "$rc"
assert_contains "G2: the refusal names the anchor" "$ERR" "anchor"
assert_eq "G2: the moved line is unchanged" 'p D:/data' "$(cat "$FX/README.md")"
assert_eq "G2: the other file in the run is unchanged" 'o D:/data' "$(cat "$FX/other.md")"

FX=$(new_fixture eol)
printf '%s\r\n' 'first' 'v D:/data' 'last' >"$FX/eol.md"
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:/data' --root "$ROOT")
assert_contains "G2: the row anchor hashes prev, line, next without CR" "$OUT" \
  $'\teol.md\t2\t3\texact\tdefault\t'"$(anchor 'v D:/data' 'first' 'last')"$'\t'
mapfile -t S < <(sites "$OUT" eol.md:2)
printf '%s\n' 'first' 'v D:/data' 'last' >"$FX/eol.md"
rc=0
vs apply --old 'D:/data' --new 'E:/work' --root "$ROOT" "${S[@]}" >/dev/null || rc=$?
assert_exit "G2: a CRLF-to-LF conversion after find still applies" 0 "$rc"
assert_eq "G2: the converted file gets the edit" $'first\nv E:/work\nlast' "$(cat "$FX/eol.md")"

# --- G3: control bytes in the text column are escaped --------------------------------
FX=$(new_fixture shown)
printf 'a\rv D:/data \x1b[0m\x7f end\\x\tt\r\n' >"$FX/ctl.md"
stage "$FX"
ROOT=$(host_path "$FX")
OUT=$(vs find --old 'D:/data' --root "$ROOT")
assert_eq "G3: CR, ESC and DEL show as \\xNN, tab as \\t, a backslash as is" \
  'a\x0dv D:/data \x1b[0m\x7f end\x\tt' "$(printf '%s\n' "$OUT" | awk -F'\t' '$2 == "ctl.md" { print $8 }')"
assert_not_contains "G3: no raw CR in find output" "$OUT" $'\r'
assert_not_contains "G3: no raw ESC in find output" "$OUT" $'\x1b'

echo
echo "value-sites.test.sh: $((CASE_NUM - FAILED)) passed, $FAILED failed, $SKIPPED skipped"
if [[ "$FAILED" -gt 0 ]]; then
  echo "value-sites.test.sh: $FAILED of $CASE_NUM FAILED" >&2
  exit 1
fi
echo "value-sites.test.sh: all $CASE_NUM passed"
