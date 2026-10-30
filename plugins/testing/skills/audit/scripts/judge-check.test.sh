#!/usr/bin/env bash
# Tests for judge-check.sh, the judge pass's shape key and comment-only check,
# and the judge-lib.sh functions it runs (judge::rkey, judge::comment_only).
# Every expected value is written by hand from the rule the script states.
# test-scope: plugins/testing/hooks/test-judge-prompt.md
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/judge-check.sh"
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
same() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected '$3', got '$2'"; fi; }
differ() { if [[ -n "$2" && -n "$3" && "$2" != "$3" ]]; then pass "$1"; else fail "$1" "expected two different keys, got '$2' and '$3'"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
# A TMPDIR inside a work tree would put the no-repository fixture in one.
export GIT_CEILING_DIRECTORIES="$TMP"
REPO="$TMP/repo"
mkdir -p "$REPO/a" "$REPO/b" "$REPO/c" "$TMP/norepo"
git -C "$REPO" init -q

# cs_test <path> <test name> [extra first line]: an xUnit file whose one test
# spans lines 4-7, or 5-8 with the extra first line.
cs_test() {
  {
    [[ -z "${3:-}" ]] || printf '%s\n' "$3"
    printf '%s\n' 'using Xunit;' 'public class CalcTests' '{' \
      "    [Fact] public void $2()" '    {' '        Assert.Equal(3, Calc.Add(1, 2));' '    }' '}'
  } >"$1"
}

# --- shape -------------------------------------------------------------------
cs_test "$REPO/a/CalcTests.cs" Adds_one
cs_test "$REPO/b/CalcTests.cs" Adds_two
cs_test "$REPO/c/CalcTests.cs" Adds_one 'using System;'
ka="$(bash "$CHECK" shape sonnet medium "$REPO/a/CalcTests.cs" 1 4-7 Adds_one)"
kb="$(bash "$CHECK" shape sonnet medium "$REPO/b/CalcTests.cs" 1 4-7 Adds_two)"
kc="$(bash "$CHECK" shape sonnet medium "$REPO/c/CalcTests.cs" 1 5-8 Adds_one)"
ko="$(bash "$CHECK" shape opus medium "$REPO/a/CalcTests.cs" 1 4-7 Adds_one)"
kh="$(bash "$CHECK" shape sonnet high "$REPO/a/CalcTests.cs" 1 4-7 Adds_one)"
if [[ "$ka" =~ ^[0-9a-f]{32}$ ]]; then pass "a shape key is 32 hex digits"; else fail "a shape key is 32 hex digits" "got '$ka'"; fi
same "two tests that differ only in name, in files otherwise the same, share a key" "$kb" "$ka"
differ "the same body under different surrounding lines gets another key" "$kc" "$ka"
differ "another judge class gets another key" "$ko" "$ka"
differ "another effort gets another key" "$kh" "$ka"

printf '%s\n' 'using Xunit;' 'public class CalcTests' '{' \
  '    [Fact] public void Adds_one()' '    {' '        Assert.Equal(3,    Calc.Add(1, 2));  ' '    }' '}' >"$REPO/b/Spaced.cs"
same "whitespace runs inside a line do not change the key" \
  "$(bash "$CHECK" shape sonnet medium "$REPO/b/Spaced.cs" 1 4-7 Adds_one)" "$ka"
printf '%s\n' 'using Xunit;' 'public class CalcTests' '{' \
  '    [Fact] public void Adds_one()' '    {' '        Assert.Equal(4, Calc.Add(1, 2));' '    }' '}' >"$REPO/b/Other.cs"
differ "another expected value gets another key" \
  "$(bash "$CHECK" shape sonnet medium "$REPO/b/Other.cs" 1 4-7 Adds_one)" "$ka"

same "a whole-file block has no key" "$(bash "$CHECK" shape sonnet medium "$REPO/a/CalcTests.cs" 0 1-8 CalcTests.cs)" ""
same "a range past the end of the file has no key" "$(bash "$CHECK" shape sonnet medium "$REPO/a/CalcTests.cs" 1 4-40 Adds_one)" ""
cs_test "$TMP/norepo/CalcTests.cs" Adds_one
same "a file in no repository has no key" "$(bash "$CHECK" shape sonnet medium "$TMP/norepo/CalcTests.cs" 1 4-7 Adds_one)" ""

# --- comment-only ------------------------------------------------------------
# diff_of <file> <changed copy>: a unified diff with a/ and b/ labels.
diff_of() { diff -u --label "a/${1#"$REPO"/}" --label "b/${1#"$REPO"/}" "$1" "$2" >"$TMP/d.diff"; }
F="$REPO/a/CalcTests.cs"
awk 'NR == 6 { print "        // the expected value is from the spec" } { print }' "$F" >"$TMP/mod"
diff_of "$F" "$TMP/mod"
bash "$CHECK" comment-only "$F" "$TMP/d.diff"
same "a C# diff that only adds a // line is comment-only" "$?" 0
awk 'NR == 6 { print "        /* the expected value"; print "         * is from the spec */" } { print }' "$F" >"$TMP/mod"
diff_of "$F" "$TMP/mod"
bash "$CHECK" comment-only "$F" "$TMP/d.diff"
same "a C# diff that only adds a /* */ block is comment-only" "$?" 0
awk 'NR == 6 { print ""; print "        // see the spec" } { print }' "$F" >"$TMP/mod"
diff_of "$F" "$TMP/mod"
bash "$CHECK" comment-only "$F" "$TMP/d.diff"
same "a blank line and a comment are comment-only" "$?" 0
sed '6s/Equal(3,/Equal(1 + 2,/' "$F" >"$TMP/mod"
diff_of "$F" "$TMP/mod"
bash "$CHECK" comment-only "$F" "$TMP/d.diff"
same "a diff that changes the expected value is code" "$?" 1
sed '6s/$/ \/\/ from the spec/' "$F" >"$TMP/mod"
diff_of "$F" "$TMP/mod"
bash "$CHECK" comment-only "$F" "$TMP/d.diff"
same "a trailing comment on an assertion line is code: the line changed" "$?" 1

P="$REPO/a/test_calc.py"
printf '%s\n' 'def test_adds():' '    assert add(1, 2) == 3' >"$P"
printf '%s\n' 'def test_adds():' '    # the spec says 3' '    assert add(1, 2) == 3' >"$TMP/mod"
diff_of "$P" "$TMP/mod"
bash "$CHECK" comment-only "$P" "$TMP/d.diff"
same "a Python diff that only adds a # line is comment-only" "$?" 0
R="$REPO/a/calc_spec.rb"
printf '%s\n' 'it "adds" do' '  expect(add(1, 2)).to eq(3)' 'end' >"$R"
printf '%s\n' 'it "adds" do' '  # the spec says 3' '  expect(add(1, 2)).to eq(3)' 'end' >"$TMP/mod"
diff_of "$R" "$TMP/mod"
bash "$CHECK" comment-only "$R" "$TMP/d.diff"
same "a language with no known comment syntax is never comment-only" "$?" 1

# --- usage -------------------------------------------------------------------
bash "$CHECK" 2>/dev/null
same "no mode is a usage error" "$?" 2
bash "$CHECK" shape sonnet medium "$F" 1 4-7 2>/dev/null
same "shape with a missing argument is a usage error" "$?" 2
bash "$CHECK" comment-only "$F" "$TMP/missing.diff" 2>/dev/null
same "comment-only with no diff file is a usage error" "$?" 2

echo
if ((FAILED == 0)); then echo "all passed"; else echo "$FAILED failed"; fi
((FAILED == 0))
