#!/usr/bin/env bash
# Regression guard for #1253: plugin prose must never name a `pN-*` priority value,
# qualified or bare. CHANGELOG.md is exempt as a historical record.
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

# Anchored on the value, not a `priority:` qualifier, so the bare flag-doc form matches.
# The leading alternation is a POSIX-ERE word boundary (no GNU `\b`): `up2-medium` does not match.
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
    grep -vE '/CHANGELOG\.md$|/evals/' |
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
