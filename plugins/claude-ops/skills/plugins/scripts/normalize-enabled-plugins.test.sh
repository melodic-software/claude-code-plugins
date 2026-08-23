#!/usr/bin/env bash
# Self-contained tests for normalize-enabled-plugins.sh.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORM="$SCRIPT_DIR/normalize-enabled-plugins.sh"
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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required" >&2
  exit 0
fi

rc=0
bash "$NORM" --help >/dev/null || rc=$?
assert_exit "--help exits 0" 0 "$rc"

rc=0
bash "$NORM" --bogus >/dev/null 2>&1 || rc=$?
assert_exit "unknown argument exits 2" 2 "$rc"

MISSING="$TEST_TMPDIR/no-such.json"
rc=0
out="$(bash "$NORM" --file "$MISSING")" || rc=$?
assert_exit "missing file is a no-op" 0 "$rc"
assert_eq "missing file reports already-sorted" "already-sorted keys=0" "$out"

SORTED="$TEST_TMPDIR/sorted.json"
printf '%s\n' '{"enabledPlugins":{"ai-slop@m":false,"x@m":true}}' >"$SORTED"
rc=0
out="$(bash "$NORM" --file "$SORTED")" || rc=$?
assert_exit "already-sorted exits 0" 0 "$rc"
assert_eq "already-sorted reports key count" "already-sorted keys=2" "$out"
assert_eq "already-sorted does not rewrite the file" \
  '{"enabledPlugins":{"ai-slop@m":false,"x@m":true}}' "$(cat "$SORTED")"

UNSORTED="$TEST_TMPDIR/unsorted.json"
printf '%s\n' '{"other":1,"enabledPlugins":{"x@m":true,"ai-slop@m":false,"context-budget@m":true}}' >"$UNSORTED"
rc=0
out="$(bash "$NORM" --file "$UNSORTED" --check)" || rc=$?
assert_exit "--check on unsorted exits 1" 1 "$rc"
assert_eq "--check reports would-normalize" "would-normalize keys=3" "$out"
assert_contains "--check does not rewrite" "$(cat "$UNSORTED")" '"x@m":true,"ai-slop@m":false'

rc=0
out="$(bash "$NORM" --file "$UNSORTED")" || rc=$?
assert_exit "unsorted write exits 0" 0 "$rc"
assert_eq "write reports normalized" "normalized keys=3" "$out"
assert_eq "keys are alphabetical after the write" \
  '["ai-slop@m","context-budget@m","x@m"]' \
  "$(jq -c '.enabledPlugins | keys_unsorted' "$UNSORTED")"
assert_eq "values are unchanged" \
  '{"ai-slop@m":false,"context-budget@m":true,"x@m":true}' \
  "$(jq -cS '.enabledPlugins' "$UNSORTED")"
assert_eq "sibling keys survive" "1" "$(jq -r '.other' "$UNSORTED")"

# A second pass is a no-op.
rc=0
out="$(bash "$NORM" --file "$UNSORTED")" || rc=$?
assert_exit "second pass is already-sorted" 0 "$rc"
assert_eq "second pass does not claim a write" "already-sorted keys=3" "$out"

BAD="$TEST_TMPDIR/bad.json"
printf '%s\n' '{not json' >"$BAD"
rc=0
out="$(bash "$NORM" --file "$BAD" 2>&1)" || rc=$?
assert_exit "malformed JSON exits 2" 2 "$rc"
assert_contains "malformed JSON is refused loudly" "$out" "unreadable-json"

PROJECT="$TEST_TMPDIR/project-settings.json"
printf '%s\n' '{"enabledPlugins":{"z@m":true,"a@m":false}}' >"$PROJECT"
before="$(cat "$PROJECT")"
rc=0
out="$(bash "$NORM" --report-project "$PROJECT")" || rc=$?
assert_exit "--report-project on unsorted exits 0" 0 "$rc"
assert_eq "--report-project names the unsorted map" "project-unsorted keys=2" "$out"
assert_eq "--report-project never writes" "$before" "$(cat "$PROJECT")"

printf '%s\n' '{"enabledPlugins":{"a@m":false,"z@m":true}}' >"$PROJECT"
rc=0
out="$(bash "$NORM" --report-project "$PROJECT")" || rc=$?
assert_exit "--report-project on sorted exits 0" 0 "$rc"
assert_eq "--report-project names the sorted map" "project-sorted keys=2" "$out"

rc=0
bash "$NORM" --report-project "$PROJECT" --file "$UNSORTED" >/dev/null 2>&1 || rc=$?
assert_exit "--report-project cannot combine with --file" 2 "$rc"

# Write denial is loud. chmod a-w is not enforced on every filesystem
# (Windows Git Bash); skip rather than green-light an unexercised branch.
DENIED="$TEST_TMPDIR/denied.json"
printf '%s\n' '{"enabledPlugins":{"z@m":true,"a@m":false}}' >"$DENIED"
chmod a-w "$DENIED" 2>/dev/null || true
if [[ -w "$DENIED" ]]; then
  printf 'SKIP: write-denied case — chmod a-w not enforced on this filesystem\n'
else
  rc=0
  out="$(bash "$NORM" --file "$DENIED" 2>&1)" || rc=$?
  assert_exit "an unwritable file exits 2" 2 "$rc"
  assert_contains "write denial is named" "$out" "write-denied"
fi
chmod u+w "$DENIED" 2>/dev/null || true

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
