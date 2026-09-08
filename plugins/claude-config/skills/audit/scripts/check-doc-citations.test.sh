#!/usr/bin/env bash
# Self-contained tests for check-doc-citations.sh (no external test lib; ships with the plugin).
#
# Fixture rows carry backticked spans that must reach the file unexpanded, so
# single quotes are the correct spelling.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-doc-citations.sh"
MANIFEST="$SCRIPT_DIR/../reference/doc-citations.tsv"
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
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

# --- Case 1: every span present on fixture pages passes --------------------
fx="$TEST_TMPDIR/present"
mkdir -p "$fx"
man="$TEST_TMPDIR/manifest-present.tsv"
printf '%s\n' '# comment' 'alpha	### `keyOne`' 'alpha	a sentence with `code`' 'beta	The space before a trailing `*` is part of the rule' >"$man"
printf '%s\n' '# alpha' '### `keyOne`' 'prose, a sentence with `code` inside' >"$fx/alpha.md"
printf '%s\n' '* **The space before a trailing `*` is part of the rule.** more' >"$fx/beta.md"
rc=0
out=$(SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 1: all present exits 0" 0 "$rc"
assert_contains "case 1: OK rows" "$out" "OK    alpha: ### \`keyOne\`"
assert_contains "case 1: summary counts" "$out" "Checked 3 citation(s), 0 missing, 0 skipped"

# --- Case 2: a span the page lost is a MISS and exit 1 ------------------------
man="$TEST_TMPDIR/manifest-missing.tsv"
printf '%s\n' 'alpha	### `keyOne`' 'alpha	### `keyGone`' >"$man"
rc=0
out=$(SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 2: missing span exits 1" 1 "$rc"
assert_contains "case 2: MISS row names the span" "$out" "MISS  alpha: ### \`keyGone\`"
assert_contains "case 2: summary counts the miss" "$out" "1 missing"

# --- Case 3: an unreadable page is a SKIP, never a pass or a failure -----------
man="$TEST_TMPDIR/manifest-skip.tsv"
printf '%s\n' 'alpha	### `keyOne`' 'gamma	anything' 'gamma	anything else' >"$man"
rc=0
out=$(SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" --manifest "$man" 2>&1) || rc=$?
assert_exit "case 3: skip does not fail" 0 "$rc"
assert_contains "case 3: SKIP line printed once per page" "$out" "SKIP  gamma: page could not be read"
assert_contains "case 3: summary counts skips" "$out" "2 skipped"
assert_not_contains "case 3: no OK claimed for the skipped page" "$out" "OK    gamma"

# --- Case 4: --docs-dir pages are read before any fetch -------------------------
# A fake curl on PATH records every call and fails, so the run proves both that
# a page on disk is never fetched and that an unreadable fetch is a SKIP.
fakebin="$TEST_TMPDIR/bin"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/curl-calls"\nexit 22\n' "$TEST_TMPDIR" >"$fakebin/curl"
chmod +x "$fakebin/curl"
man="$TEST_TMPDIR/manifest-docs.tsv"
printf '%s\n' 'alpha	### `keyOne`' 'delta	never fetched span' >"$man"
rc=0
out=$(PATH="$fakebin:$PATH" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="" bash "$SCRIPT" --manifest "$man" --docs-dir "$fx" 2>&1) || rc=$?
assert_exit "case 4: docs-dir page satisfies the row, failed fetch is a skip" 0 "$rc"
assert_contains "case 4: OK from the docs dir" "$out" "OK    alpha"
assert_contains "case 4: the unfetchable page is skipped" "$out" "SKIP  delta"
calls="$(cat "$TEST_TMPDIR/curl-calls" 2>/dev/null || true)"
assert_not_contains "case 4: the on-disk page was never fetched" "$calls" "alpha.md"
assert_contains "case 4: the absent page was fetched once" "$calls" "delta.md"

# --- Case 5: fatal cases ---------------------------------------------------------
rc=0
bash "$SCRIPT" --manifest "$TEST_TMPDIR/absent.tsv" >/dev/null 2>&1 || rc=$?
assert_exit "case 5: missing manifest exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --nope >/dev/null 2>&1 || rc=$?
assert_exit "case 5: unknown argument exits 2" 2 "$rc"

# --- Case 6: the shipped manifest is well-formed --------------------------------
rc=0
bad=$(grep -vE '^(#|$)' "$MANIFEST" | grep -vcE $'^[a-z-]+\t.+$' || true)
if [[ "$bad" == "0" ]]; then pass "case 6: every manifest row is slug<TAB>span"; else fail "case 6: every manifest row is slug<TAB>span" "$bad malformed row(s)"; fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
