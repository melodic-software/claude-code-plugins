#!/usr/bin/env bash
# Regression guard for #1253: skill/reference prose must never name a `pN-*`
# priority value in ANY form the removed prose used — qualified with no space
# (`priority:p2-medium`), qualified with a space (`priority: p2-medium`), or
# bare, as the `--priority` flag documentation listed it (`p2-medium`). That
# scheme exists in no governed repository — the live fleet-wide `priority:` set
# is critical/high/medium/low/needs-triage — so an autonomous pass that follows
# a `pN-*` routing instruction literally fails applying a nonexistent label
# (label-taxonomy.md "Universal axes": priority members are discovered live,
# never snapshotted in skill text).
#
# CHANGELOG.md is deliberately exempt: it is an immutable historical record of
# what a past release actually shipped, not a routing instruction consumed by a
# skill invocation, so it is never rewritten to match the current scheme.
#
# Two cases: (1) a synthetic fixture proves the detector itself catches the
# banned pattern (self-test, so a broken regex can't silently pass), and (2) a
# real scan of the plugin's shipped prose proves the corpus is clean today.
# shellcheck disable=SC2016  # fixture bodies are literal prose in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/.." && pwd)"

PASS=0
FAIL=0
ok() {
  printf 'PASS: %s\n' "$1"
  PASS=$((PASS + 1))
}
fail() {
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
  FAIL=$((FAIL + 1))
}

# ERE for the banned value itself: p<0-3>-<word>, e.g. p2-medium. Anchoring on
# the value rather than on a `priority:` qualifier is deliberate — the removed
# `--priority <p>` flag documentation listed the members bare, so a guard keyed
# to the qualifier would let that exact line back in. The leading alternation is
# a POSIX-ERE word boundary (no GNU `\b`), so `up2-medium` does not match while
# `priority:p2-medium`, `priority: p2-medium`, and a bare `p2-medium` all do.
PATTERN='(^|[^a-z0-9])p[0-3]-[a-z]+'

# --- (1) self-test: the detector catches a synthetic hit -------------------
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

assert_detects() {
  local label="$1" body="$2" file
  file="$fixture_dir/$(printf '%s' "$label" | tr -c 'a-z0-9' '-').md"
  printf '%s\n' "$body" >"$file"
  if grep -qE "$PATTERN" "$file"; then
    ok "detector matches $label"
  else
    fail "detector matches $label" "regex did not match: $body"
  fi
}

assert_detects 'the qualified colon-no-space form' \
  'Default to `priority:p2-medium` when no directive sets one.'
assert_detects 'the qualified colon-space form' \
  'Default to `priority: p2-medium` when no directive sets one.'
assert_detects 'a bare flag-value listing' \
  '`--priority <p>` -- Priority label (e.g., `p0-critical`, `p2-medium`, `p3-low`)'

assert_clean() {
  local label="$1" body="$2" file
  file="$fixture_dir/clean-$(printf '%s' "$label" | tr -c 'a-z0-9' '-').md"
  printf '%s\n' "$body" >"$file"
  if grep -qE "$PATTERN" "$file"; then
    fail "detector does not false-positive on $label" "regex matched: $body"
  else
    ok "detector does not false-positive on $label"
  fi
}

assert_clean 'live-resolution prose' \
  'Resolve the live `priority:` label set from the bound adapter at action entry.'
assert_clean 'a longer word ending in the pN- shape' \
  'The up2-medium and step2-milestone tokens are unrelated identifiers.'

# --- (2) real scan: the shipped plugin corpus is clean ----------------------
mapfile -t hits < <(
  grep -rlE "$PATTERN" --include='*.md' "$PLUGIN_ROOT" 2>/dev/null |
    grep -v '/CHANGELOG\.md$' |
    grep -v '/evals/' |
    sort
)

if [[ ${#hits[@]} -eq 0 ]]; then
  ok "no pN-* priority literal in plugin prose (CHANGELOG.md exempt)"
else
  fail "no pN-* priority literal in plugin prose (CHANGELOG.md exempt)" "found in: ${hits[*]}"
fi

echo "---"
echo "passed: $PASS, failed: $FAIL"
if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
exit 0
