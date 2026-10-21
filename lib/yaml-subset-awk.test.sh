#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks and $ in the single-quoted test names and inputs are literal YAML text
# Tests for lib/yaml-subset.awk's refusals of a tab indent, of an unquoted
# `: ` inside a plain value, of flow mappings and of document markers. Expected records and exit codes come from the
# parser's header: `key<TAB>value` per scalar, and on a parse error one
# `error<TAB><line><TAB><message>` record and exit 1.
# Run directly: bash lib/yaml-subset-awk.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWK="$SCRIPT_DIR/yaml-subset.awk"

FAILED=0
CASE_NUM=0
check() { # check <label> <expected stdout> <expected exit> <input> [awk -v args]
  local label="$1" want="$2" want_rc="$3" input="$4" out rc
  shift 4
  out="$(printf '%b' "$input" | awk "$@" -f "$AWK")"
  rc=$?
  CASE_NUM=$((CASE_NUM + 1))
  if [[ "$out" == "$want" && "$rc" == "$want_rc" ]]; then
    printf 'PASS: %s\n' "$label"
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL: %s\n  expected: [%s] exit %s\n  actual:   [%s] exit %s\n' "$label" "$want" "$want_rc" "$out" "$rc" >&2
  fi
}

T=$'\t'
# -v STRICT=1: a key repeated in one mapping is a parse error at the second
# occurrence; without it both records print as before.
check 'a repeated key keeps both records without STRICT' "a${T}1"$'\n'"b${T}2"$'\n'"a${T}3" 0 'a: 1\nb: 2\na: 3\n'
check 'a repeated key fails under STRICT at the second line' "a${T}1"$'\n'"b${T}2"$'\n'"error${T}3${T}duplicate key \`a\` (first at line 1)" 1 'a: 1\nb: 2\na: 3\n' -v STRICT=1
check 'a repeated nested key fails under STRICT' "m.k${T}1"$'\n'"error${T}3${T}duplicate key \`m.k\` (first at line 2)" 1 'm:\n  k: 1\n  k: 2\n' -v STRICT=1
check 'the same key under two parents is not a duplicate under STRICT' "a.k${T}1"$'\n'"b.k${T}2" 0 'a:\n  k: 1\nb:\n  k: 2\n' -v STRICT=1
check 'the same key in two sequence items is not a duplicate under STRICT' "l.0.k${T}1"$'\n'"l.1.k${T}2" 0 'l:\n  - k: 1\n  - k: 2\n' -v STRICT=1
check 'a key repeated inside one sequence item fails under STRICT' "l.0.k${T}1"$'\n'"error${T}3${T}duplicate key \`l.0.k\` (first at line 2)" 1 'l:\n  - k: 1\n    k: 2\n' -v STRICT=1
check 'a tab indent on line 1 is a parse error' "error${T}1${T}tab indentation" 1 '\tkey: v\n'
check 'a tab after a space indent is a parse error' "error${T}2${T}tab indentation" 1 'a:\n \tb: v\n'
check 'a tab indent on a later line is a parse error' "a${T}1"$'\n'"error${T}2${T}tab indentation" 1 'a: 1\n\tb: 2\n'
check 'a space base indent still reads' "key${T}v" 0 '  key: v\n'
check 'a tab inside a value is not indentation' "key${T}a${T}b" 0 'key: a\tb\n'
check 'a tab base indent in a BLOCK=1 fence still reads' "block${T}1"$'\n'"key${T}v" 0 '```yaml config\n\tkey: v\n```\n' -v BLOCK=1
check 'a tab below the base indent in a BLOCK=1 fence is a parse error' "block${T}1"$'\n'"error${T}3${T}tab indentation" 1 '```yaml config\na:\n\tb: v\n```\n' -v BLOCK=1

check 'an unquoted `: ` in a value is a parse error' "error${T}1${T}a plain value may not hold \`: \`; quote it" 1 'key: a: b\n'
check 'an unquoted `:` then a tab in a value is a parse error' "error${T}1${T}a plain value may not hold \`: \`; quote it" 1 'key: a:\tb\n'
check 'an unquoted `: ` in a sequence item is a parse error' "error${T}2${T}a plain value may not hold \`: \`; quote it" 1 'l:\n  - a b: c\n'
check 'a double-quoted `: ` reads without its quotes' "key${T}a: b" 0 'key: "a: b"\n'
check 'a single-quoted `: ` reads without its quotes' "key${T}a: b" 0 "key: 'a: b'\n"
check 'a colon with no space after it stays legal' "key${T}http://x" 0 'key: http://x\n'
check 'a trailing colon stays legal' "key${T}a:" 0 'key: a:\n'
check 'a `: ` inside a comment is not part of the value' "key${T}a" 0 'key: a  # note: b\n'
# Flow mappings and document markers are outside the subset, as in
# lib/yaml-subset.mjs, whose messages these are.
FLOW="flow mapping ({...}) is outside the subset; use block style"
MARK="document markers are outside the subset"
check 'a flow-mapping value is a parse error' "a${T}1"$'\n'"error${T}2${T}${FLOW}" 1 'a: 1\nm: {k: 1}\n'
check 'an empty flow mapping is a parse error' "error${T}1${T}${FLOW}" 1 'm: {}\n'
check 'a flow mapping as a sequence item is a parse error' "error${T}2${T}${FLOW}" 1 'l:\n  - {k: 1}\n'
check 'a flow mapping inside a flow sequence is a parse error' "l.0${T}a"$'\n'"error${T}1${T}${FLOW}" 1 'l: [a, {k: 1}]\n'
check 'a `{` inside a plain value stays legal' "k${T}a{b}" 0 'k: a{b}\n'
check 'a `---` marker is a parse error' "a${T}1"$'\n'"error${T}2${T}${MARK}" 1 'a: 1\n---\na: 2\n'
check 'a leading `---` marker is a parse error' "error${T}1${T}${MARK}" 1 '---\na: 1\n'
check 'a `...` marker is a parse error' "a${T}1"$'\n'"error${T}2${T}${MARK}" 1 'a: 1\n...\n'
check 'a `---` marker inside a BLOCK=1 fence is a parse error' "block${T}1"$'\n'"error${T}3${T}${MARK}" 1 '---\n```yaml config\n---\na: 1\n```\n' -v BLOCK=1
check 'a nested map item still reads' "l.0.x${T}y" 0 'l:\n  - x: y\n'

# Long blank runs: a plain value keeps its inner blanks, a flow item likewise,
# and blanks before `#` start a comment. All three lines read within 1 s.
SP="$(printf '%*s' 200000 '')"
want="k${T}a${SP}x"$'\n'"l.0${T}b${SP}c"$'\n'"m${T}d"
start=$(date +%s%N)
out="$(printf 'k: a%sx\nl: [b%sc]\nm: d%s#e\n' "$SP" "$SP" "$SP" | LC_ALL=C timeout 10 awk -f "$AWK")"
rc=$?
ms=$((($(date +%s%N) - start) / 1000000))
CASE_NUM=$((CASE_NUM + 1))
if [[ "$out" == "$want" && "$rc" == 0 && "$ms" -lt 1000 ]]; then
  printf 'PASS: 200,000-blank runs parse in under 1 s (%s ms)\n' "$ms"
else
  FAILED=$((FAILED + 1))
  printf 'FAIL: 200,000-blank runs parse in under 1 s\n  exit %s after %s ms, output %s\n' "$rc" "$ms" "$([[ "$out" == "$want" ]] && echo matches || echo differs)" >&2
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
