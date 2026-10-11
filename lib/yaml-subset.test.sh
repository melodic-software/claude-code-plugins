#!/usr/bin/env bash
# Tests for lib/yaml-subset.awk's refusals of a tab indent and of an unquoted
# `: ` inside a plain value. Expected records and exit codes come from the
# parser's header: `key<TAB>value` per scalar, and on a parse error one
# `error<TAB><line><TAB><message>` record and exit 1.
# Run directly: bash lib/yaml-subset.test.sh
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
check 'a nested map item still reads' "l.0.x${T}y" 0 'l:\n  - x: y\n'

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
