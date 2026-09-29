#!/usr/bin/env bash
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-publisher-token-alignment.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PUBLISHER_TOKEN='@melodic-software/[a-z-]+'
write_org() { printf '# org tokens\nfleet-id %s\n' "$1" >"$TMP/org.txt"; }
write_port() { printf '# --- ACTIVE ---\n%s\n# --- STAGED ---\n# staged\n' "$1" >"$TMP/port.txt"; }

# run <expected-exit> <name>: run the script against the fixtures in $TMP.
run() {
  local expected="$1" name="$2" status
  LAST_OUTPUT="$(
    PUBLISHER_TOKEN_ORG_FILE="$TMP/org.txt" \
      PUBLISHER_TOKEN_PORT_FILE="$TMP/port.txt" \
      bash "$SCRIPT" 2>&1
  )"
  status=$?
  if [[ "$status" -eq "$expected" ]]; then
    pass "$name"
  else
    bad "$name" "expected exit $expected, got $status; output: $LAST_OUTPUT"
  fi
}

write_org "$PUBLISHER_TOKEN"
write_port "$PUBLISHER_TOKEN"
run 0 "aligned publisher-like active token passes"

printf 'fleet-id   %s  \r\n' "$PUBLISHER_TOKEN" >"$TMP/org.txt"
write_port "  $PUBLISHER_TOKEN	"
run 0 "surrounding whitespace on either side does not break alignment"

write_org 'other-token'
run 1 "publisher-like active token absent from org file fails"
assert_output_contains "failure names the token" "$PUBLISHER_TOKEN"

write_org "$PUBLISHER_TOKEN"
printf '# --- INACTIVE ---\n%s\n# --- STAGED ---\n' "$PUBLISHER_TOKEN" >"$TMP/port.txt"
run 2 "renamed ACTIVE marker exits 2"
assert_output_contains "marker failure is named" 'no "# --- ACTIVE" marker'

write_port '# only a comment'
run 2 "ACTIVE section holding only comments exits 2"
assert_output_contains "empty-active failure is named" "no active tokens"

write_port "$PUBLISHER_TOKEN"
: >"$TMP/org.txt"
run 2 "empty org file exits 2"
assert_output_contains "empty-org failure is named" "no org patterns"

write_org "$PUBLISHER_TOKEN"
rm -f "$TMP/org.txt"
run 2 "missing org file exits 2"
assert_output_contains "missing-file failure is named" "missing token file"

write_org "$PUBLISHER_TOKEN"
rm -f "$TMP/port.txt"
run 2 "missing portability file exits 2"

if bash "$SCRIPT" >/dev/null 2>&1; then
  ok "real token files align"
else
  fail "real token files should align"
fi

test_harness::report
