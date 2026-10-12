#!/usr/bin/env bash
# Black-box tests for lib/suppression-scan.py: the marker catalog, the
# justified predicate, --diff, --count, --correctness-rules and the exit codes.
# Every expected value below is read off the fixture lines this file writes.
# Run directly: bash lib/suppression-scan.test.sh
# shellcheck disable=SC2016 # `$(...)` and backticks here are fixture text, never expanded
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/suppression-scan.py"
PY="${PYTHON:-python3}"

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
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}

# One line per record: `<file>:<line> <tool> <rules joined by ,> <yes|no>`.
summarize() {
  "$PY" -c '
import json, sys
for r in json.load(sys.stdin):
    print("%s:%d %s %s %s" % (r["file"], r["line"], r["tool"], ",".join(r["rules"]) or "-", "yes" if r["justified"] else "no"))
'
}

TREE="$TEST_TMPDIR/tree"
mkdir -p "$TREE"
put() { printf '%s\n' "${@:2}" >"$TREE/$1"; }

put a.js \
  'foo(); // eslint-disable-line no-console -- CLI prints to stdout' \
  '// eslint-disable-next-line no-console' \
  '/* eslint-disable */' \
  'bar(); // eslint-disable-line -- a reason but no rule id' \
  'const s = "// eslint-disable-line no-console";'
put b.ts \
  '// @ts-expect-error the fixture passes a string on purpose' \
  '// @ts-ignore' \
  'const t = "// @ts-ignore";'
put c.py \
  'x = 1  # noqa: E501 long URL in an example' \
  'y = 2  # noqa: E501' \
  'z = 3  # noqa' \
  'import os  # type: ignore[import-untyped]  # stubs are not published' \
  'def f(a, b, c, d, e, g):  # pylint: disable=too-many-arguments' \
  '    v = a._p  # pyright: ignore[reportPrivateUsage]  # the test reads the private cache' \
  '# ruff: noqa: E402' \
  's = "# noqa: E501"' \
  'DOC = """' \
  '    # noqa: E501 inside a docstring' \
  '"""' \
  'import sys  # type: ignore' \
  'w = 4  # pyright: ignore' \
  'def g(a, b, c, d, e, h):  # pylint: disable=too-many-arguments  # the signature mirrors a C API' \
  '# ruff: noqa: F401 re-exports for the public API'
put d.sh \
  '# shellcheck disable=SC2086 # word splitting is wanted here' \
  '# shellcheck disable=SC2034,SC2154' \
  'echo "# shellcheck disable=SC2086"' \
  "cat <<'EOF'" \
  "it's a heredoc line" \
  'EOF' \
  '# shellcheck disable=SC2155 # the value is exported as soon as it is read'
put e.cs \
  '#pragma warning disable CS0618 // the replacement API is not on net48' \
  '#pragma warning disable CS0168' \
  '[SuppressMessage("Design", "CA1031:DoNotCatchGeneralExceptionTypes", Justification = "the worker logs and retries")]' \
  '[SuppressMessage("Design", "CA1062")]' \
  '[SuppressMessage(' \
  '    "Style", "IDE0060:Remove unused parameter",' \
  '    Justification = "kept for the interface")]' \
  'var m = "[SuppressMessage(\"Design\", \"CA1062\")]";'
put f.go \
  'defer f.Close() //nolint:errcheck // a read-only file has nothing to flush' \
  'x := y //nolint' \
  's := "//nolint:errcheck"' \
  'y := z // nolint:errcheck'
put g.ps1 \
  "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'interactive console output')]" \
  "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]" \
  "Write-Output \"SuppressMessageAttribute('PSAvoidUsingWriteHost', '')\""
put h.md \
  '<!-- markdownlint-disable-next-line MD013 --> <!-- the table row cannot wrap -->' \
  '<!-- markdownlint-disable MD033 -->' \
  'Use `<!-- markdownlint-disable MD013 -->` sparingly.' \
  '```html' \
  '<!-- markdownlint-disable MD041 -->' \
  '```'
put i.rb \
  'def call # rubocop:disable Metrics/MethodLength -- the state machine reads top to bottom' \
  '# rubocop:todo Style/Documentation, Layout/LineLength'
put j.java \
  '@SuppressWarnings("unchecked") // the generic array comes from a raw legacy API' \
  '@SuppressWarnings({"rawtypes", "unchecked"})' \
  'String s = "@SuppressWarnings(\"unchecked\")";'

expected="a.js:1 eslint no-console yes
a.js:2 eslint no-console no
a.js:3 eslint - no
a.js:4 eslint - no
b.ts:1 typescript - yes
b.ts:2 typescript - no
c.py:1 noqa E501 yes
c.py:2 noqa E501 no
c.py:3 noqa - no
c.py:4 mypy import-untyped yes
c.py:5 pylint too-many-arguments no
c.py:6 pyright reportPrivateUsage yes
c.py:7 ruff E402 no
c.py:12 mypy - no
c.py:13 pyright - no
c.py:14 pylint too-many-arguments yes
c.py:15 ruff F401 yes
d.sh:1 shellcheck SC2086 yes
d.sh:2 shellcheck SC2034,SC2154 no
d.sh:7 shellcheck SC2155 yes
e.cs:1 csharp CS0618 yes
e.cs:2 csharp CS0168 no
e.cs:3 csharp CA1031 yes
e.cs:4 csharp CA1062 no
e.cs:5 csharp IDE0060 yes
f.go:1 golangci-lint errcheck yes
f.go:2 golangci-lint - no
g.ps1:1 powershell PSAvoidUsingWriteHost yes
g.ps1:2 powershell PSUseShouldProcessForStateChangingFunctions no
h.md:1 markdownlint MD013 yes
h.md:2 markdownlint MD033 no
i.rb:1 rubocop Metrics/MethodLength yes
i.rb:2 rubocop Style/Documentation,Layout/LineLength no
j.java:1 java unchecked yes
j.java:2 java rawtypes,unchecked no"

out="$(cd "$TREE" && "$PY" "$SCANNER" .)"
assert_eq "inventory exits 0" 0 "$?"
assert_eq "the catalog finds every marker with its rules and justification, and none in a string, code span or fence" \
  "$expected" "$(printf '%s' "$out" | summarize)"

reasons="$(printf '%s' "$out" | "$PY" -c '
import json, sys
for r in json.load(sys.stdin):
    if r["file"] in ("a.js", "c.py") and r["line"] in (1, 4):
        print("%s:%d %s" % (r["file"], r["line"], r["reason"]))
')"
assert_eq "the reason is the text after the rule ids" \
  "a.js:1 CLI prints to stdout
a.js:4 a reason but no rule id
c.py:1 long URL in an example
c.py:4 stubs are not published" "$reasons"

out="$(cd "$TREE" && "$PY" "$SCANNER" --count a.js)"
assert_eq "--count prints both lines" "suppressions=4
unjustified=3" "$out"

printf '%s\n' '# listed correctness rules' 'no-console' '' 'sc2086' >"$TEST_TMPDIR/rules"
out="$(cd "$TREE" && "$PY" "$SCANNER" --correctness-rules "$TEST_TMPDIR/rules" a.js d.sh |
  "$PY" -c '
import json, sys
print(" ".join("%s:%d" % (r["file"], r["line"]) for r in json.load(sys.stdin) if r["correctness"]))
')"
assert_eq "--correctness-rules flags each record naming a listed rule, case-insensitively" "a.js:1 a.js:2 d.sh:1" "$out"

out="$(cd "$TREE" && "$PY" "$SCANNER" --count --correctness-rules "$TEST_TMPDIR/rules" a.js d.sh)"
assert_eq "--count adds the correctness line when rules are listed" "suppressions=7
unjustified=4
correctness=3" "$out"

# ---- --diff -------------------------------------------------------------------
REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO"
g() { git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
printf '%s\n' 'a = 1  # noqa: E501' 'b = 2' >"$REPO/old.py"
printf '%s\n' 'm = 1  # noqa: E731' 'n = 2' >"$REPO/m.py"
printf '%s\n' 'r = 1  # noqa: F401' >"$REPO/r.py"
g add -A
g commit -q -m base
g switch -q -c topic
printf '%s\n' 'a = 1  # noqa: E501' 'b = 2' 'c = 3  # noqa: E741' >"$REPO/old.py"
printf '%s\n' 'n = 2' >"$REPO/m.py"
printf '%s\n' 'k = 0' 'm = 1  # noqa: E731' >"$REPO/n.py"
g mv r.py r2.py
printf '%s\n' '# shellcheck disable=SC2086' >"$REPO/with space.sh"
printf '%s\n' '# shellcheck disable=SC2154' >"$REPO/-dash.sh"
printf '%s\n' '# shellcheck disable=SC2034' >"$REPO/\$(touch pwned).sh"
g add -A
g commit -q -m topic
printf '%s\n' 'u = 1  # noqa: E999' >>"$REPO/old.py"

out="$(cd "$REPO" && "$PY" "$SCANNER" --diff main | summarize)"
assert_eq "--diff reports only lines main...HEAD adds; a moved line once, a renamed file's old line not at all" \
  '$(touch pwned).sh:1 shellcheck SC2034 no
-dash.sh:1 shellcheck SC2154 no
n.py:2 noqa E731 no
old.py:3 noqa E741 no
with space.sh:1 shellcheck SC2086 no' "$out"
if [[ -e "$REPO/pwned" ]]; then fail "a file name is never evaluated" "pwned exists"; else pass "a file name is never evaluated"; fi

out="$(cd "$REPO" && "$PY" "$SCANNER" --diff main -- -dash.sh 'with space.sh' | summarize)"
assert_eq "--diff with paths keeps only those files" '-dash.sh:1 shellcheck SC2154 no
with space.sh:1 shellcheck SC2086 no' "$out"

printf '%s\n' 'with space.sh' >"$TEST_TMPDIR/paths"
out="$(cd "$REPO" && "$PY" "$SCANNER" --diff main --paths-from "$TEST_TMPDIR/paths" | summarize)"
assert_eq "--paths-from reads one path per line" 'with space.sh:1 shellcheck SC2086 no' "$out"

out="$(cd "$REPO" && "$PY" "$SCANNER" r2.py | summarize)"
assert_eq "inventory mode still lists the renamed file's suppression" 'r2.py:1 noqa F401 no' "$out"

# ---- exit 2 -------------------------------------------------------------------
expect_usage() {
  local name="$1" out rc
  shift
  out="$(cd "$TREE" && "$PY" "$SCANNER" "$@" 2>/dev/null)"
  rc=$?
  assert_eq "$name exits 2" 2 "$rc"
  assert_eq "$name prints nothing on stdout" "" "$out"
}
expect_usage "an unknown flag" --bogus
expect_usage "a missing path" does-not-exist.py
expect_usage "a missing correctness-rules file" --correctness-rules "$TEST_TMPDIR/none" a.js
expect_usage "a missing paths-from file" --paths-from "$TEST_TMPDIR/none"
out="$(cd "$REPO" && "$PY" "$SCANNER" --diff no-such-ref 2>/dev/null)"
assert_eq "an unknown --diff base exits 2 with nothing on stdout" "2:" "$?:$out"
out="$(cd "$REPO" && "$PY" "$SCANNER" --diff=--output=x 2>/dev/null)"
assert_eq "a --diff base that reads as an option exits 2" "2:" "$?:$out"
if [[ -e "$REPO/x" ]]; then fail "a base that reads as an option writes nothing" "x exists"; else pass "a base that reads as an option writes nothing"; fi
chmod 000 "$TREE/a.js"
if [[ -r "$TREE/a.js" ]]; then
  pass "an unreadable file exits 2 (skipped: this user reads mode 000 files)"
else
  expect_usage "an unreadable file" a.js
fi
chmod 644 "$TREE/a.js"

"$PY" "$SCANNER" --help >"$TEST_TMPDIR/help"
assert_eq "--help exits 0" 0 "$?"
grep -q -- '--correctness-rules' "$TEST_TMPDIR/help"
assert_eq "--help names --correctness-rules" 0 "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
exit $((FAILED > 0 ? 1 : 0))
