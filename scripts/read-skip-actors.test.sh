#!/usr/bin/env bash
# Unit tests for read-skip-actors.sh. Synthetic list files exercise the parse
# and every fail-closed shape; one case reads the real committed list so the
# published form stays a live assertion, not an example.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/read-skip-actors.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

write_list() {
  printf '%s\n' "$@" >"$TMP/list"
}

# --- comments and blanks are ignored; entries join with commas --------------
write_list "# ratified" "" "dependabot[bot]" "cursor[bot]  # org-installed" ""
if out="$(bash "$SCRIPT" "$TMP/list" 2>&1)" && [[ "$out" == "dependabot[bot],cursor[bot]" ]]; then
  ok "joins active entries with commas, dropping comments and blanks"
else
  fail "expected 'dependabot[bot],cursor[bot]', got: $out"
fi

# --- a single entry prints with no trailing comma ---------------------------
write_list "claude[bot]"
if out="$(bash "$SCRIPT" "$TMP/list" 2>&1)" && [[ "$out" == "claude[bot]" ]]; then
  ok "a single entry prints bare"
else
  fail "expected 'claude[bot]', got: $out"
fi

# --- fail-closed shapes exit 2 with nothing on stdout -----------------------
expect_exit_2() {
  local label="$1"
  shift
  local out status=0
  out="$(bash "$SCRIPT" "$@" 2>/dev/null)" || status=$?
  if [[ "$status" -eq 2 && -z "$out" ]]; then
    ok "$label exits 2 with empty stdout"
  else
    fail "$label should exit 2 with empty stdout, got status $status, out: $out"
  fi
}

expect_exit_2 "a missing file" "$TMP/no-such-file"
write_list "# only commentary" ""
expect_exit_2 "an empty active set" "$TMP/list"
write_list "dependabot[bot],cursor[bot]"
expect_exit_2 "an embedded comma" "$TMP/list"
write_list "depend abot[bot]"
expect_exit_2 "embedded whitespace" "$TMP/list"
write_list "claude[bot]"
expect_exit_2 "extra arguments" "$TMP/list" surplus

# --- the committed list parses and carries the ratified five ----------------
if out="$(bash "$SCRIPT" 2>&1)" && [[ "$out" == *"cursor[bot]"* && "$out" != *" "* ]]; then
  ok "the committed .github/claude-skip-actors parses to a spaceless list naming cursor[bot]"
else
  fail "committed list should parse and name cursor[bot], got: $out"
fi

test_harness::report
