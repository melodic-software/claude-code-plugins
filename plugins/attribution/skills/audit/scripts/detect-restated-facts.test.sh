#!/usr/bin/env bash
# Self-contained tests for detect-restated-facts.sh.
# The positive is the #3524 shape: a bare "1,536" listing-cap restatement.
# Clearance is a pointer to the skills frontmatter reference, or a four-part
# record in the window. A stamp sitting far from the sentence does not clear it.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$SCRIPT_DIR/detect-restated-facts.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $3" "exit $2"; fi
}

DIR="$TEST_TMPDIR/corpus"
mkdir -p "$DIR/sub"

cat >"$DIR/bare.md" <<'EOF'
# Listing

The combined description and when_to_use text is truncated at 1,536 characters in the skill listing.
EOF

cat >"$DIR/pointer.md" <<'EOF'
# Listing

The combined description is truncated at 1,536 characters in the skill listing.
The cap is upstream's: https://code.claude.com/docs/en/skills#frontmatter-reference.
EOF

cat >"$DIR/stamped.md" <<'EOF'
# Listing

skillListingMaxDescChars defaults to the per-entry cap.
Basis: https://example.com/skills-frontmatter. As of: 2026-08-31.
Recheck trigger: the page moves the default.
EOF

cat >"$DIR/far.md" <<'EOF'
# Listing

See https://code.claude.com/docs/en/skills#frontmatter-reference.
Verified 2026-08-31. Recheck trigger: the page moves the default.

spacer
spacer
spacer
spacer
spacer
spacer
spacer
spacer
spacer
spacer
spacer
spacer
spacer
spacer

The combined description is truncated at 1,536 characters in the skill listing.
EOF

cat >"$DIR/sub/CHANGELOG.md" <<'EOF'
# Changelog

- Truncated at 1,536 characters in the skill listing.
EOF

cat >"$DIR/fenced.md" <<'EOF'
# Example

```
truncated at 1,536 characters in the skill listing
```

Body without the constant.
EOF

cat >"$DIR/front.md" <<'EOF'
---
description: truncated at 1,536 characters in the skill listing
---

# Body

No listing cap in the body.
EOF

cat >"$DIR/both.md" <<'EOF'
skillListingBudgetFraction default 0.01 and skillListingMaxDescChars default 1536 in the skill listing.
EOF

OUT="$(bash "$CHECK" "$DIR/bare.md")"
assert_eq "bare 1,536 listing sentence is one finding" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "1"
assert_eq "the finding is the listing-entry cap" \
  "$(jq -r '.findings[0].fact_id' <<<"$OUT")" "listing-entry-cap-1536"
assert_eq "the rule id is the restated-fact rule" \
  "$(jq -r '.findings[0].rule' <<<"$OUT")" "attribution/audit/rule-restated-upstream-fact"
assert_eq "fix_eligible is false" \
  "$(jq -r '.findings[0].fix_eligible' <<<"$OUT")" "false"
assert_eq "class is restated-upstream-fact" \
  "$(jq -r '.findings[0].class' <<<"$OUT")" "restated-upstream-fact"
assert_eq "source is the skills frontmatter reference" \
  "$(jq -r '.findings[0].source_url' <<<"$OUT")" "https://code.claude.com/docs/en/skills#frontmatter-reference"

OUT="$(bash "$CHECK" "$DIR/pointer.md")"
assert_eq "a nearby official pointer clears the sentence" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "0"
assert_eq "the clear is counted" "$(jq -r '.counts.cleared' <<<"$OUT")" "1"

OUT="$(bash "$CHECK" "$DIR/stamped.md")"
assert_eq "a four-part record in the window clears the constant" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "0"

OUT="$(bash "$CHECK" "$DIR/far.md")"
assert_eq "a stamp more than the window away leaves the sentence a finding" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "1"

OUT="$(bash "$CHECK" "$DIR/sub/CHANGELOG.md")"
assert_eq "changelog history is not a finding" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "0"
assert_eq "changelog matches are declined" \
  "$(jq -r '.declined[0].reason' <<<"$OUT")" "changelog"

OUT="$(bash "$CHECK" "$DIR/fenced.md")"
assert_eq "a fenced example is not a finding" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "0"
assert_eq "fenced matches are declined" \
  "$(jq -r '.declined[0].reason' <<<"$OUT")" "fenced"

OUT="$(bash "$CHECK" "$DIR/front.md")"
assert_eq "frontmatter is not a prose finding" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "0"
assert_eq "frontmatter matches are declined" \
  "$(jq -r '.declined[0].reason' <<<"$OUT")" "frontmatter"

OUT="$(bash "$CHECK" "$DIR/both.md")"
assert_eq "each catalog constant on one line is its own finding" \
  "$(jq -r '.counts.findings' <<<"$OUT")" "3"

HELP="$(bash "$CHECK" --help 2>&1)"
rc=$?
assert_exit "--help exits 0" "$rc" "0"
case "$HELP" in
*detect-restated-facts.sh*) pass "--help names the script" ;;
*) fail "--help names the script" "contains the script name" "$HELP" ;;
esac

SHOW="$(bash "$CHECK" --show-config)"
rc=$?
assert_exit "--show-config exits 0" "$rc" "0"
case "$SHOW" in
*2026-09-28*) pass "--show-config prints the catalog as-of date" ;;
*) fail "--show-config prints the catalog as-of date" "2026-09-28" "$SHOW" ;;
esac

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
