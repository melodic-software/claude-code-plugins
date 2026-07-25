#!/usr/bin/env bash
# Regression guard for #1253: skill/reference prose must never route to a
# `priority:pN-*` label in either spacing (`priority:p2-medium` or
# `priority: p2-medium`). That scheme exists in no
# governed repository — the live fleet-wide `priority:` set is
# critical/high/medium/low/needs-triage — so an autonomous pass that follows a
# `pN-*` routing instruction literally fails applying a nonexistent label
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

# ERE for the banned scheme: priority:p<0-3>-<word>, e.g. priority:p2-medium.
# The optional whitespace after the colon matters — the live governed labels are
# written colon-space (`priority: low`), so a reintroduction is at least as
# likely to read `priority: p2-medium` as the colon-no-space form.
PATTERN='priority:[[:space:]]*p[0-3]-[a-z]+'

# --- (1) self-test: the detector catches a synthetic hit -------------------
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
fixture_file="$fixture_dir/synthetic.md"
printf 'Default to `priority:p2-medium` when no directive sets one.\n' >"$fixture_file"

if grep -qE "$PATTERN" "$fixture_file"; then
  ok "detector matches a synthetic priority:pN-* hit"
else
  fail "detector matches a synthetic priority:pN-* hit" "regex did not match the fixture"
fi

spaced_fixture="$fixture_dir/synthetic-spaced.md"
printf 'Default to `priority: p2-medium` when no directive sets one.\n' >"$spaced_fixture"

if grep -qE "$PATTERN" "$spaced_fixture"; then
  ok "detector matches the colon-space priority: pN-* form"
else
  fail "detector matches the colon-space priority: pN-* form" "regex did not match the spaced fixture"
fi

clean_fixture="$fixture_dir/clean.md"
printf 'Resolve the live `priority:` label set from the bound adapter at action entry.\n' >"$clean_fixture"
if grep -qE "$PATTERN" "$clean_fixture"; then
  fail "detector does not false-positive on live-resolution prose" "regex matched clean fixture"
else
  ok "detector does not false-positive on live-resolution prose"
fi

# --- (2) real scan: the shipped plugin corpus is clean ----------------------
mapfile -t hits < <(
  grep -rlE "$PATTERN" --include='*.md' "$PLUGIN_ROOT" 2>/dev/null \
    | grep -v '/CHANGELOG\.md$' \
    | grep -v '/evals/' \
    | sort
)

if [[ ${#hits[@]} -eq 0 ]]; then
  ok "no priority:pN-* routing literal in plugin prose (CHANGELOG.md exempt)"
else
  fail "no priority:pN-* routing literal in plugin prose (CHANGELOG.md exempt)" "found in: ${hits[*]}"
fi

echo "---"
echo "passed: $PASS, failed: $FAIL"
if [[ $FAIL -ne 0 ]]; then
  exit 1
fi
exit 0
