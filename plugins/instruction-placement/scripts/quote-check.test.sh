#!/usr/bin/env bash
# Regression tests for quote-check.sh.
#
# Every case runs on page snapshots through QUOTE_CHECK_FIXTURE_DIR, so no case
# touches the network. The snapshots go through the real fetch-docs.sh and
# docs-cache.sh, so a change to either that breaks the check fails here.
# test-scope: plugins/instruction-placement/scripts/fetch-docs.sh
# test-scope: plugins/instruction-placement/scripts/docs-cache.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/quote-check.sh"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi
}

# --------------------------------------------------------------------------
# Fixtures: an index listing two pages, and a snapshot of only one of them
# --------------------------------------------------------------------------
FIXTURE="$SCRATCH/pages"
mkdir -p "$FIXTURE"
cat >"$FIXTURE/llms.txt" <<'EOF'
# Claude Code Docs

- [Memory](https://code.claude.com/docs/en/memory.md): how Claude remembers your project
- [Skills](https://code.claude.com/docs/en/skills.md): extend Claude with skills
EOF
cat >"$FIXTURE/memory.md" <<'EOF'
# Manage Claude's memory

## How `CLAUDE.md` files load

Claude Code loads `CLAUDE.md` from your current working directory and every directory above it. See [the load order](/en/memory#load-order) for **details**.

Nested files load on demand.

## Compaction

| What | After compaction |
| --- | --- |
| Project-root CLAUDE.md | Re-injected from disk |

## Other section

Rules load at startup when they have no paths.
A **glob** like `src/**/*.md` stays as written.
EOF

URL=https://code.claude.com/docs/en
SOURCES="$SCRATCH/sources.tsv"
# shellcheck disable=SC2016 # the backticks are markdown code spans in the quotes
{
  printf 'id\turl\tquote\tas_of\n'
  printf 'T-1\t%s/memory#how-claude-md-files-load\t%s\t2026-10-27\n' "$URL" \
    'Claude Code loads `CLAUDE.md` from your current working directory and every directory above it.'
  printf 'T-2\t%s/memory#how-claude-md-files-load\t%s\t2026-10-27\n' "$URL" 'See the load order for details.'
  printf 'T-3\t%s/memory#compaction\t%s\t2026-10-27\n' "$URL" 'Project-root CLAUDE.md | Re-injected from disk'
  printf 'T-4\t%s/memory#other-section\t%s\t2026-10-27\n' "$URL" 'Rules load at launch when they have no paths.'
  printf 'T-5\t%s/memory#compaction\t%s\t2026-10-27\n' "$URL" 'Nested files load on demand.'
  printf 'T-6\t%s/memory#gone-section\t%s\t2026-10-27\n' "$URL" 'A sentence under a removed heading.'
  printf 'T-7\t%s/skills#frontmatter-reference\t%s\t2026-10-27\n' "$URL" 'A sentence on a page with no snapshot.'
  printf 'T-8\t%s/hooks#hook-events\t%s\t2026-10-20\n' "$URL" 'A sentence on a page the index does not list.'
  printf 'T-9\t%s/memory#other-section\t%s\t2026-10-27\n' "$URL" 'A glob like `src/**/*.md` stays as written.'
  printf 'T-10\t%s/memory\t%s\t2026-10-27\n' "$URL" 'Nested files load on demand.'
  printf 'T-11\t%s/memory#compaction\t\t2026-10-27\n' "$URL"
} >"$SOURCES"

run_fixture() {
  QUOTE_CHECK_FIXTURE_DIR="$FIXTURE" QUOTE_CHECK_SOURCES="$1" bash "$SCRIPT" 2>"$SCRATCH/stderr"
}

# --------------------------------------------------------------------------
# One run over every case
# --------------------------------------------------------------------------
OUT="$(run_fixture "$SOURCES")"
RC=$?
assert_eq "drift and unverified results still exit 0" "0" "$RC"

EXPECTED="verified T-1
verified T-2
verified T-3
drift T-4 $URL/memory#other-section
  stored:  Rules load at launch when they have no paths.
  fetched: Rules load at startup when they have no paths.
drift T-5 $URL/memory#compaction
  stored:  Nested files load on demand.
  fetched: (no sentence in the section shares a word with the quote)
drift T-6 $URL/memory#gone-section
  stored:  A sentence under a removed heading.
  fetched: (the page has no section #gone-section)
unverified T-7 as of 2026-10-27
unverified T-8 as of 2026-10-20
verified T-9
verified T-10"
assert_eq "one result per well-formed record, in list order" "$EXPECTED" "$OUT"

# The same cases, line by line, so a failure names the one that broke.
assert_contains "a matching snapshot is verified" "$OUT" "verified T-1"
assert_contains "link markup and bold are dropped before matching" "$OUT" "verified T-2"
assert_contains "a table row matches with its cells joined by ' | '" "$OUT" "verified T-3"
assert_contains "a changed sentence is drift, with the stored wording" "$OUT" \
  "  stored:  Rules load at launch when they have no paths."
assert_contains "a changed sentence is drift, with the fetched wording" "$OUT" \
  "  fetched: Rules load at startup when they have no paths."
assert_contains "a quote found only in another section is drift" "$OUT" "drift T-5 "
assert_contains "a heading gone from the page is drift" "$OUT" "(the page has no section #gone-section)"
assert_contains "a missing snapshot is unverified as of its date" "$OUT" "unverified T-7 as of 2026-10-27"
assert_contains "a page the index does not list is unverified" "$OUT" "unverified T-8 as of 2026-10-20"
assert_contains "bold is dropped outside code spans and kept inside them" "$OUT" "verified T-9"
assert_contains "a URL with no anchor is checked against the whole page" "$OUT" "verified T-10"
assert_contains "a record with an empty quote is skipped, and said so" "$(cat "$SCRATCH/stderr")" \
  "skipped a record that is not id, url, quote, as_of: T-11"

# --------------------------------------------------------------------------
# Arguments and the list
# --------------------------------------------------------------------------
ERR="$(bash "$SCRIPT" extra-arg 2>&1 >/dev/null)"
RC=$?
assert_eq "an argument exits 2" "2" "$RC"
assert_contains "an argument prints the usage" "$ERR" "Usage: quote-check.sh"

ERR="$(bash "$SCRIPT" https://code.claude.com/docs/en/memory 2>&1 >/dev/null)"
RC=$?
assert_eq "a URL argument is refused" "2" "$RC"

OUT="$(bash "$SCRIPT" --help 2>/dev/null)"
RC=$?
assert_eq "--help exits 0" "0" "$RC"
assert_contains "--help prints the usage" "$OUT" "Usage: quote-check.sh"

run_fixture "$SCRATCH/no-such-list.tsv" >/dev/null
RC=$?
assert_eq "an unreadable list exits 2" "2" "$RC"
assert_contains "an unreadable list says which" "$(cat "$SCRATCH/stderr")" "no-such-list.tsv"

printf 'id\turl\tquote\tas_of\n' >"$SCRATCH/empty.tsv"
OUT="$(run_fixture "$SCRATCH/empty.tsv")"
RC=$?
assert_eq "a list with no records exits 0" "0" "$RC"
assert_eq "a list with no records prints nothing" "" "$OUT"

# --------------------------------------------------------------------------
# Every fetch goes through fetch-docs.sh
# --------------------------------------------------------------------------
assert_eq "the script calls no curl or wget of its own" "" "$(grep -nE 'curl|wget' "$SCRIPT")"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
