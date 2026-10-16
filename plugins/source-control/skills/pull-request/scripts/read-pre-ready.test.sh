#!/usr/bin/env bash
# Tests for read-pre-ready.sh. Expected outputs follow the pre_ready contract in
# reference/ready-for-review.md: an absent key runs every step, a listed
# `enabled: false` turns that one step off, and anything the reader cannot
# trust (an unknown step, a bad value, a file it cannot parse) runs every step.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/read-pre-ready.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

ALL_ON=$'base-merge\tenabled\nplan-evidence\tenabled\ncode-review\tenabled\nsecurity-review\tenabled\nverify\tenabled'

read_doc() { printf '%s' "$1" | bash "$SCRIPT" - 2>/dev/null; }

out=$(read_doc '')
assert_eq "an empty document runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"

out=$(read_doc $'pr_open_state: ready\n')
assert_eq "a file without pre_ready runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"

out=$(read_doc $'pre_ready: []\n')
assert_eq "an empty list runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"

out=$(read_doc $'pre_ready:\n  - step: base-merge\n    enabled: true\n  - step: code-review\n    enabled: false\n  - step: verify\n    enabled: true\n')
assert_eq "a disabled step is off and every other step stays on" \
  $'source\tconfig\nbase-merge\tenabled\nplan-evidence\tenabled\ncode-review\tdisabled\nsecurity-review\tenabled\nverify\tenabled' "$out"

out=$(read_doc $'pre_ready: [{step: security-review, enabled: false}, {step: plan-evidence, enabled: false}]  # flow form\n')
assert_eq "the flow form disables the steps it names" \
  $'source\tconfig\nbase-merge\tenabled\nplan-evidence\tdisabled\ncode-review\tenabled\nsecurity-review\tdisabled\nverify\tenabled' "$out"

# Each untrusted shape: the source line fails closed with a reason, and every step is on.
check_fail_closed() {
  local label="$1" doc="$2" reason="$3" got
  got=$(read_doc "$doc")
  assert_eq "$label runs every step" $'source\tfail-closed\t'"$reason"$'\n'"$ALL_ON" "$got"
}

check_fail_closed "an unknown step" \
  $'pre_ready:\n  - step: code-review\n    enabled: false\n  - step: lint\n    enabled: false\n' "unknown step 'lint' in pre_ready"
check_fail_closed "a step listed twice" \
  $'pre_ready:\n  - step: verify\n    enabled: true\n  - step: verify\n    enabled: false\n' "step 'verify' is listed twice in pre_ready"
check_fail_closed "an enabled value other than true or false" \
  $'pre_ready:\n  - step: verify\n    enabled: maybe\n' "step 'verify' has enabled 'maybe', not true or false"
check_fail_closed "an item with no enabled value" \
  $'pre_ready:\n  - step: verify\n' "step 'verify' has no enabled value in pre_ready"
check_fail_closed "an item with no step" \
  $'pre_ready:\n  - enabled: false\n' "pre_ready item 0 has no step"
check_fail_closed "a list of bare step names" \
  $'pre_ready: [verify]\n' "pre_ready item 0 is not a {step, enabled} mapping"
check_fail_closed "a scalar pre_ready" \
  $'pre_ready: none\n' "pre_ready is not a list"
check_fail_closed "a mapping keyed by step" \
  $'pre_ready:\n  verify:\n    enabled: false\n' "pre_ready is a mapping, not a list"
check_fail_closed "a file the parser rejects" \
  $'pre_ready:\n\t- step: verify\n' "docs/conventions/source-control.yaml does not parse"

check_fail_closed "a tab inside a quoted step name, turned into a space," \
  $'pre_ready:\n  - step: "lint\\tx"\n    enabled: false\n' "unknown step 'lint x' in pre_ready"

# The reader is at least as strict as schemas/source-control.schema.json.
check_fail_closed "an item holding only unknown keys before an unknown step" \
  $'pre_ready:\n  - step: code-review\n    enabled: false\n  - note: x\n  - step: lint\n    enabled: false\n' "pre_ready item 1 has an unknown key 'note'"
check_fail_closed "an empty item between two steps" \
  $'pre_ready:\n  - step: code-review\n    enabled: false\n  - {}\n  - step: verify\n    enabled: false\n' "pre_ready item 1 has no step"
check_fail_closed "an extra key inside an item" \
  $'pre_ready:\n  - step: verify\n    enabled: false\n    why: x\n' "pre_ready item 0 has an unknown key 'why'"
check_fail_closed "a quoted enabled value" \
  $'pre_ready:\n  - step: verify\n    enabled: "false"\n' "an enabled value in pre_ready is quoted, not a boolean"
check_fail_closed "a quoted enabled value in the flow form" \
  $'pre_ready: [{step: verify, enabled: \'false\'}]\n' "an enabled value in pre_ready is quoted, not a boolean"
check_fail_closed "an enabled value with a trailing slash" \
  $'pre_ready:\n  - step: verify\n    enabled: false/\n' "step 'verify' has enabled 'false/', not true or false"
check_fail_closed "a nested list item" \
  $'pre_ready:\n  -\n    - verify\n' "pre_ready item 0 is not a {step, enabled} mapping"
check_fail_closed "a repeated pre_ready key" \
  $'pre_ready: []\npre_ready:\n  - step: verify\n    enabled: false\n' "pre_ready appears more than once"
check_fail_closed "a repeated key inside an item" \
  $'pre_ready:\n  - step: verify\n    enabled: false\n    step: code-review\n' "pre_ready item 0 repeats a key"

# --http-response reads a `gh api -i` response: the status line decides.
read_response() { printf '%s' "$1" | bash "$SCRIPT" --http-response 2>/dev/null; }

out=$(read_response $'HTTP/2.0 200 OK\r\nContent-Type: application/vnd.github.raw\r\n\r\npre_ready:\n  - step: verify\n    enabled: false\n')
assert_eq "a 200 response is read as the document" \
  $'source\tconfig\nbase-merge\tenabled\nplan-evidence\tenabled\ncode-review\tenabled\nsecurity-review\tenabled\nverify\tdisabled' "$out"
out=$(read_response $'HTTP/2.0 404 Not Found\r\nContent-Type: application/json\r\n\r\n{"message":"Not Found"}')
assert_eq "a 404 response runs every step by default" $'source\tdefault\n'"$ALL_ON" "$out"
out=$(read_response $'HTTP/2.0 502 Bad Gateway\r\n\r\n')
assert_eq "a 5xx response fails closed and runs every step" \
  $'source\tfail-closed\tthe base read returned HTTP/2.0 502 Bad Gateway\n'"$ALL_ON" "$out"
out=$(read_response '')
assert_eq "no response fails closed and runs every step" \
  $'source\tfail-closed\tthe base read returned no response\n'"$ALL_ON" "$out"

bash "$SCRIPT" >/dev/null 2>&1
assert_exit "no argument is a usage error" 2 "$?"
bash "$SCRIPT" "$TEST_TMPDIR/source-control.yaml" >/dev/null 2>&1
assert_exit "a working-tree path is refused" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
