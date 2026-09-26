#!/usr/bin/env bash
# Tests for catalog.sh against fixture catalogs written into a temp dir.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/catalog.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

cat_file="$TMP/good.md"
printf '%s\n' \
  '# Playbook: fixture' \
  '' \
  '## Phase 1: code' \
  '' \
  '### dead-code' \
  '' \
  '- skill: code-tidying:audit-dead-code' \
  '- args: .' \
  '- applies-when: repo has source code' \
  '- checked: true' \
  '- issue: #4503' \
  '' \
  '#### Override' \
  '' \
  'Stay on the current branch.' \
  '- skill: not-a-key:ignored' \
  '' \
  '#### Notes' \
  '' \
  'Resolve or delete only.' \
  '' \
  '## Phase 2: prose' \
  '' \
  '### residue-dissolve' \
  '' \
  '- skill: code-tidying:audit-comment-residue, code-tidying:dissolve-comments' \
  '- args:' \
  '- applies-when: always' \
  '- checked: false' \
  >"$cat_file"

T=$'\t'
expected="dead-code${T}Phase 1: code${T}code-tidying:audit-dead-code${T}.${T}true${T}#4503${T}repo has source code
residue-dissolve${T}Phase 2: prose${T}code-tidying:audit-comment-residue, code-tidying:dissolve-comments${T}${T}false${T}${T}always"
assert_eq "TSV rows in file order; override text never parsed as a key" "$expected" "$(bash "$SCRIPT" "$cat_file")"
assert_eq "every row keeps 7 columns, empty fields included" "7
7" "$(bash "$SCRIPT" "$cat_file" | awk -F'\t' '{print NF}')"

assert_eq "--override prints the block, blank edges trimmed" "Stay on the current branch.
- skill: not-a-key:ignored" "$(bash "$SCRIPT" --override dead-code "$cat_file")"
assert_eq "--notes prints the notes block" "Resolve or delete only." "$(bash "$SCRIPT" "$cat_file" --notes dead-code)"
out=$(bash "$SCRIPT" --override residue-dissolve "$cat_file")
assert_eq "entry without an override: exit 0" "0" "$?"
assert_eq "entry without an override: empty output" "" "$out"
out=$(bash "$SCRIPT" --override no-such-id "$cat_file" 2>/dev/null)
assert_eq "unknown id: exit 1" "1" "$?"
assert_eq "unknown id: no stdout" "" "$out"

crlf="$TMP/crlf.md"
awk '{ printf "%s\r\n", $0 }' "$cat_file" >"$crlf"
assert_eq "CRLF catalog parses the same" "$expected" "$(bash "$SCRIPT" "$crlf")"

bad_run() { # <label> <file> <stderr-substring>
  local out err rc
  out=$(bash "$SCRIPT" "$2" 2>"$TMP/err")
  rc=$?
  err=$(cat "$TMP/err")
  assert_eq "$1: non-zero exit" "1" "$rc"
  assert_eq "$1: no stdout" "" "$out"
  case "$err" in *"$3"*) pass "$1: stderr names the problem" ;; *) fail "$1: stderr" "*$3*" "$err" ;; esac
}

printf '%s\n' '## Phase 1: x' '### a' '- skill: p:s' '### b' '- skill: p:t' '### a' '- skill: p:u' >"$TMP/dup.md"
bad_run "duplicate id" "$TMP/dup.md" "duplicate id: a"

printf '%s\n' '### a' '- skill: p:s' '### b' '- args: .' '#### Override' '- skill: p:hidden' >"$TMP/noskill.md"
bad_run "entry with no skill line" "$TMP/noskill.md" "b has no skill"

printf '%s\n' '### a' '- skill:' '- args: .' >"$TMP/emptyskill.md"
bad_run "entry with an empty skill value" "$TMP/emptyskill.md" "a has no skill"

bash "$SCRIPT" >/dev/null 2>&1
assert_eq "no catalog argument: usage exit 2" "2" "$?"

if ((FAILED)); then
  printf '%d FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'catalog.test.sh: all passed\n'
