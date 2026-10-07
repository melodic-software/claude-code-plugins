#!/usr/bin/env bash
# Self-contained tests for lib/docs-raw.sh (no external test lib; the copies ship with the plugins).
#
# No case touches the network: every case sets the docs fixture seam, so
# fetch-docs.sh reads pages from a fixture directory.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/docs-raw.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
while IFS= read -r v; do unset "$v"; done < <(compgen -e DOCS_CACHE_)
export HOME="$TEST_TMPDIR/suite-home" XDG_CONFIG_HOME="$TEST_TMPDIR/suite-config"
export FETCH_DOCS_FIXTURE_DIR="$TEST_TMPDIR/fx" DOCS_CACHE_DIR="$TEST_TMPDIR/cache" FETCH_DOCS_CLAUDE_BIN=""

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}

mkdir -p "$FETCH_DOCS_FIXTURE_DIR"
printf '%s\n' '# Docs' \
  '- [Small](https://code.claude.com/docs/en/small.md): s' \
  '- [Big](https://code.claude.com/docs/en/big.md): b' \
  '- [Huge](https://code.claude.com/docs/en/huge.md): h' >"$FETCH_DOCS_FIXTURE_DIR/llms.txt"
# 19 bytes without the trailing newline, counted by hand: "# Small" (7) + "\n\n" (2) + "Body line." (10).
printf '# Small\n\nBody line.\n' >"$FETCH_DOCS_FIXTURE_DIR/small.md"
printf '# Big\n\nintro\n\n## Alpha\n\nalpha text\n\n## Beta\n\nbeta text\n' >"$FETCH_DOCS_FIXTURE_DIR/big.md"
{
  printf '# Huge\n\n## One\n\n'
  for _ in $(seq 1 1200); do printf '%s\n' 'one line of sixty bytes of filler text for the size cap xx'; done
  printf '\n## Two\n\ntwo\n'
} >"$FETCH_DOCS_FIXTURE_DIR/huge.md"

# 1. A page at or under the whole-page threshold prints whole, with its byte count.
out="$(bash "$SCRIPT" https://code.claude.com/docs/en/small)"
head1="$(head -1 <<<"$out")"
assert_eq "case 1: small page is read whole" "state=read kind=page bytes=19" \
  "$(grep -oE 'state=read|kind=[a-z-]+|bytes=[0-9]+' <<<"$head1" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "case 1: body is the page" $'# Small\n\nBody line.' "$(tail -n +2 <<<"$out")"
if [[ "$head1" =~ sha256=[0-9a-f]{64} ]]; then pass "case 1: header carries the page sha256"; else fail "case 1: sha256" "$head1"; fi

# 2. Over the threshold, the body is the bare section map, not the page.
out="$(DOCS_CACHE_WHOLE_PAGE_BYTES=20 bash "$SCRIPT" 'https://code.claude.com/docs/en/big#beta')"
head1="$(head -1 <<<"$out")"
assert_eq "case 2: the fragment is dropped from the URL" "url=https://code.claude.com/docs/en/big" "$(grep -oE 'url=[^ ]+' <<<"$head1")"
assert_eq "case 2: kind is map" "kind=map" "$(grep -oE 'kind=[a-z-]+' <<<"$head1")"
assert_eq "case 2: map rows name the sections" "Big|Big > Alpha|Big > Beta" "$(tail -n +2 <<<"$out" | cut -f7 | paste -sd'|' -)"

# 3. With ids, the body is those sections only.
out="$(DOCS_CACHE_WHOLE_PAGE_BYTES=20 bash "$SCRIPT" https://code.claude.com/docs/en/big 3)"
assert_eq "case 3: kind is sections" "kind=sections" "$(head -1 <<<"$out" | grep -oE 'kind=[a-z-]+')"
assert_eq "case 3: body is the Beta section" $'## Beta\n\nbeta text' "$(tail -n +2 <<<"$out")"

# 4. A slug the index does not list is unread with its reason, and exits 0.
rc=0
out="$(bash "$SCRIPT" https://code.claude.com/docs/en/missing)" || rc=$?
assert_eq "case 4: exit 0" "0" "$rc"
assert_eq "case 4: unread header" "docs-raw: url=https://code.claude.com/docs/en/missing state=unread reason=not-in-index" "$out"

# 5. A request the cache would answer with the whole page is too-large, with no body.
out="$(bash "$SCRIPT" https://code.claude.com/docs/en/huge 2)"
assert_eq "case 5: kind too-large" "kind=too-large" "$(head -1 <<<"$out" | grep -oE 'kind=[a-z-]+')"
assert_eq "case 5: no body" "1" "$(wc -l <<<"$out" | tr -d ' ')"
out="$(bash "$SCRIPT" https://code.claude.com/docs/en/huge 3)"
assert_eq "case 5: a small section of the same page still prints" $'## Two\n\ntwo' "$(tail -n +2 <<<"$out")"

# 6. With the cache disabled the page is read from the fetched file.
out="$(DOCS_CACHE_ENABLED=false bash "$SCRIPT" https://code.claude.com/docs/en/small)"
assert_eq "case 6: page without a cache entry" $'# Small\n\nBody line.' "$(tail -n +2 <<<"$out")"
out="$(DOCS_CACHE_ENABLED=false DOCS_CACHE_WHOLE_PAGE_BYTES=20 bash "$SCRIPT" https://code.claude.com/docs/en/big 2)"
assert_eq "case 6: sections without a cache entry" $'## Alpha\n\nalpha text' "$(tail -n +2 <<<"$out")"

# 7. Arguments that are not an https URL and section ids are refused before any fetch.
for args in "http://code.claude.com/docs/en/small" "file:///etc/passwd" "https://code.claude.com/docs/en/small 1;id" \
  "https://code.claude.com/docs/en/small 0" "https://code.claude.com/docs/en/small --file"; do
  rc=0
  # shellcheck disable=SC2086 # the cases split on purpose
  bash "$SCRIPT" $args >/dev/null 2>&1 || rc=$?
  assert_eq "case 7: refused: $args" "2" "$rc"
done
rc=0
bash "$SCRIPT" $'https://code.claude.com/docs/en/small\nx' >/dev/null 2>&1 || rc=$?
assert_eq "case 7: refused: a URL with a newline" "2" "$rc"
rc=0
bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "case 7: refused: no URL" "2" "$rc"

if [[ $FAILED -gt 0 ]]; then
  printf '\n%d failure(s)\n' "$FAILED" >&2
  exit 1
fi
printf '\nall passed\n'
