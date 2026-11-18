#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

host_path() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
SCRIPT="$(host_path "$SCRIPT_DIR/cross-repo-dups.py")"

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

crd() { MSYS_NO_PATHCONV=1 python3 "$SCRIPT" "$@"; }

new_repo() {
  local fx="$TEST_TMPDIR/$1"
  mkdir -p "$fx"
  git -C "$fx" init -q
  git -C "$fx" config user.email t@example.com
  git -C "$fx" config user.name t
  git -C "$fx" config commit.gpgsign false
  git -C "$fx" remote add origin "https://github.com/acme/$1.git"
  printf '%s' "$fx"
}
put() {
  local fx="$1" rel="$2"
  shift 2
  mkdir -p "$(dirname "$fx/$rel")"
  printf '%s\n' "$@" >"$fx/$rel"
}
commit() { git -C "$1" add -A && git -C "$1" commit -qm fixture; }
row() { printf '%s\n' "$2" | awk -F'\t' -v k="$1" '$1 == k' || true; }

A=$(new_repo api)
B=$(new_repo web)
C=$(new_repo ops)
for r in "$A" "$B" "$C"; do
  put "$r" scripts/retry.sh '#!/bin/sh' 'n=0' 'until "$@"; do n=$((n+1)); [ $n -ge 3 ] && exit 1; done'
done
put "$A" lib/slugify.py 'def slug(s):' '    return s.lower().replace(" ", "-")' '' 'X = 1'
put "$B" src/slugify.py 'def slug(s):' '    return s.lower().replace(" ", "-")' '' 'X = 2'
put "$A" README.md 'api'
put "$B" README.md 'web'
put "$A" .github/lint.yml 'rules: strict'
put "$B" .github/lint.yml 'rules: strict'
put "$A" gen/schema.json '// GENERATED from schema.ts. Do not edit.' '{"a": 1}'
put "$B" gen/schema.json '// GENERATED from schema.ts. Do not edit.' '{"a": 1}'
put "$A" tests/fixtures/sample.txt 'same'
put "$B" tests/fixtures/sample.txt 'same'
for r in "$A" "$B" "$C"; do commit "$r"; done

OUT=$(crd "$(host_path "$A")" "$(host_path "$B")" "$(host_path "$C")")
assert_exit "R1: three repos exit 0" 0 $?

EXACT=$(row exact "$OUT")
assert_contains "R2: retry.sh copied in 3 repos is one exact row" "$EXACT" $'exact\t3\t3\tacme/api:scripts/retry.sh | acme/ops:scripts/retry.sh | acme/web:scripts/retry.sh'
assert_contains "R3: unmanaged lint config is an exact row" "$EXACT" $'exact\t2\t2\tacme/api:.github/lint.yml | acme/web:.github/lint.yml'
assert_not_contains "R4: generated file is not an exact row" "$EXACT" "schema.json"
assert_not_contains "R5: fixture path is not an exact row" "$EXACT" "sample.txt"

DIV=$(row diverged "$OUT")
assert_contains "R6: slugify.py drifted copies are one diverged row" "$DIV" $'diverged\t2\t2\t0.75\tslugify.py\tacme/api:lib/slugify.py | acme/web:src/slugify.py'
assert_not_contains "R7: README.md is a generic name, never diverged" "$DIV" "README.md"

assert_contains "R8: generated copies counted" "$OUT" $'excluded\tgenerated\t2'
assert_contains "R9: fixture copies counted" "$OUT" $'excluded\tpath\t2'
assert_contains "R10: ref row names origin fallback" "$OUT" $'ref\tacme/api\tHEAD'

put "$TEST_TMPDIR" managed.txt '# sync manifest destinations' '.github/lint.yml' 'acme/ops:scripts/retry.sh'
OUT=$(crd --managed "$(host_path "$TEST_TMPDIR/managed.txt")" "$(host_path "$A")" "$(host_path "$B")" "$(host_path "$C")")
EXACT=$(row exact "$OUT")
assert_not_contains "M1: a managed path in every repo drops out" "$EXACT" "lint.yml"
assert_contains "M2: a per-repo managed entry drops only that copy" "$EXACT" $'exact\t2\t2\tacme/api:scripts/retry.sh | acme/web:scripts/retry.sh'
assert_contains "M3: managed copies counted" "$OUT" $'excluded\tmanaged\t3'

OUT=$(printf '%s\n' "one=$(host_path "$A")" "two=$(host_path "$B")" | crd --repos-from -)
assert_contains "L1: LABEL=PATH from --repos-from labels the rows" "$(row exact "$OUT")" "one:scripts/retry.sh | two:scripts/retry.sh"

crd "$(host_path "$A")" >/dev/null 2>&1
assert_exit "E1: one repository exits 2" 2 $?
mkdir -p "$TEST_TMPDIR/plain"
OUT=$(crd "$(host_path "$A")" "$(host_path "$TEST_TMPDIR/plain")" 2>/dev/null)
assert_exit "E2: a folder with no commit leaves one repo and exits 2" 2 $?
assert_contains "E3: the unreadable folder is a skip row" "$OUT" $'skip\tplain\t'

echo
echo "cross-repo-dups.test.sh: $((CASE_NUM - FAILED)) passed, $FAILED failed"
if [[ "$FAILED" -gt 0 ]]; then
  echo "cross-repo-dups.test.sh: $FAILED of $CASE_NUM FAILED" >&2
  exit 1
fi
echo "cross-repo-dups.test.sh: all $CASE_NUM passed"
