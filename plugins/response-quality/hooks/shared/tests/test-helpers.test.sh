#!/usr/bin/env bash
# test-helpers.test.sh - Tests for test-helpers.sh test framework utilities
#
# Meta-test: Tests the test framework helper functions themselves.
# Uses subshells for intentional-failure tests to isolate counter modifications.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPERS_FILE="${SCRIPT_DIR}/../test-helpers.sh"

# Test counters (separate from the helpers being tested)
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

pass_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: $1"
}

fail_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: $1"
}

echo ""
echo "=========================================="
echo "Test Suite: test-helpers.sh"
echo "=========================================="
echo ""

# --- Test Section: File Structure ---
echo "--- File Structure ---"

# Test 1: Helper file exists
if [ -f "$HELPERS_FILE" ]; then
    pass_test "test-helpers.sh exists"
else
    fail_test "test-helpers.sh not found"
fi

# Test 2: Helper file has correct shebang
if head -1 "$HELPERS_FILE" | grep -q "#!/usr/bin/env bash"; then
    pass_test "test-helpers.sh has correct shebang"
else
    fail_test "test-helpers.sh missing shebang"
fi

# --- Test Section: Assert Equals ---
echo ""
echo "--- assert_equals ---"

# Test 3: assert_equals with matching strings (should pass, exit 0)
if (source "$HELPERS_FILE" && assert_equals "hello" "hello" "test" >/dev/null 2>&1); then
    pass_test "assert_equals returns 0 for matching strings"
else
    fail_test "assert_equals should return 0 for matching strings"
fi

# Test 4: assert_equals with mismatched strings (should fail, exit 1)
if (source "$HELPERS_FILE" && assert_equals "hello" "world" "test" >/dev/null 2>&1); then
    fail_test "assert_equals should return 1 for mismatched strings"
else
    pass_test "assert_equals returns 1 for mismatched strings"
fi

# --- Test Section: Assert Contains ---
echo ""
echo "--- assert_contains ---"

# Test 5: assert_contains with substring present
if (source "$HELPERS_FILE" && assert_contains "hello world" "world" "test" >/dev/null 2>&1); then
    pass_test "assert_contains returns 0 when substring found"
else
    fail_test "assert_contains should return 0 when substring found"
fi

# Test 6: assert_contains with substring absent
if (source "$HELPERS_FILE" && assert_contains "hello world" "xyz" "test" >/dev/null 2>&1); then
    fail_test "assert_contains should return 1 when substring missing"
else
    pass_test "assert_contains returns 1 when substring missing"
fi

# --- Test Section: Assert Not Contains ---
echo ""
echo "--- assert_not_contains ---"

# Test 7: assert_not_contains with substring absent
if (source "$HELPERS_FILE" && assert_not_contains "hello world" "xyz" "test" >/dev/null 2>&1); then
    pass_test "assert_not_contains returns 0 when substring absent"
else
    fail_test "assert_not_contains should return 0 when substring absent"
fi

# Test 8: assert_not_contains with substring present
if (source "$HELPERS_FILE" && assert_not_contains "hello world" "world" "test" >/dev/null 2>&1); then
    fail_test "assert_not_contains should return 1 when substring present"
else
    pass_test "assert_not_contains returns 1 when substring present"
fi

# --- Test Section: Assert File Exists ---
echo ""
echo "--- assert_file_exists ---"

# Test 9: assert_file_exists with existing file
TEMP_FILE=$(mktemp)
if (source "$HELPERS_FILE" && assert_file_exists "$TEMP_FILE" "test" >/dev/null 2>&1); then
    pass_test "assert_file_exists returns 0 for existing file"
else
    fail_test "assert_file_exists should return 0 for existing file"
fi
rm -f "$TEMP_FILE"

# Test 10: assert_file_exists with non-existent file
if (source "$HELPERS_FILE" && assert_file_exists "/nonexistent/file" "test" >/dev/null 2>&1); then
    fail_test "assert_file_exists should return 1 for missing file"
else
    pass_test "assert_file_exists returns 1 for missing file"
fi

# --- Test Section: Assert File Not Exists ---
echo ""
echo "--- assert_file_not_exists ---"

# Test 11: assert_file_not_exists with non-existent file
if (source "$HELPERS_FILE" && assert_file_not_exists "/nonexistent/file" "test" >/dev/null 2>&1); then
    pass_test "assert_file_not_exists returns 0 for missing file"
else
    fail_test "assert_file_not_exists should return 0 for missing file"
fi

# Test 12: assert_file_not_exists with existing file
TEMP_FILE=$(mktemp)
if (source "$HELPERS_FILE" && assert_file_not_exists "$TEMP_FILE" "test" >/dev/null 2>&1); then
    fail_test "assert_file_not_exists should return 1 for existing file"
else
    pass_test "assert_file_not_exists returns 1 for existing file"
fi
rm -f "$TEMP_FILE"

# --- Test Section: Assert Exit Code ---
echo ""
echo "--- assert_exit_code ---"

# Test 13: assert_exit_code with matching code
if (source "$HELPERS_FILE" && assert_exit_code 0 0 "test" >/dev/null 2>&1); then
    pass_test "assert_exit_code returns 0 for matching codes"
else
    fail_test "assert_exit_code should return 0 for matching codes"
fi

# Test 14: assert_exit_code with mismatched code
if (source "$HELPERS_FILE" && assert_exit_code 0 1 "test" >/dev/null 2>&1); then
    fail_test "assert_exit_code should return 1 for mismatched codes"
else
    pass_test "assert_exit_code returns 1 for mismatched codes"
fi

# --- Test Section: Run Command ---
echo ""
echo "--- run_command ---"

# Test 15: run_command captures output
OUTPUT=$(source "$HELPERS_FILE" && run_command "echo 'test output'" && echo "$COMMAND_OUTPUT")
if [ "$OUTPUT" = "test output" ]; then
    pass_test "run_command captures stdout correctly"
else
    fail_test "run_command should capture stdout (got: $OUTPUT)"
fi

# Test 16: run_command captures exit code
EXIT_CODE=$(source "$HELPERS_FILE" && run_command "exit 42" || true && echo "$COMMAND_EXIT_CODE")
if [ "$EXIT_CODE" = "42" ]; then
    pass_test "run_command captures exit code correctly"
else
    fail_test "run_command should capture exit code (got: $EXIT_CODE)"
fi

# --- Test Section: Utility Functions ---
echo ""
echo "--- Utility Functions ---"

# Test 17: test_suite_start outputs header
OUTPUT=$(source "$HELPERS_FILE" && test_suite_start "Test Name" 2>&1)
if echo "$OUTPUT" | grep -q "Test Name"; then
    pass_test "test_suite_start outputs suite name"
else
    fail_test "test_suite_start should output suite name"
fi

# Test 18: skip_test outputs skip message
OUTPUT=$(source "$HELPERS_FILE" && skip_test "skip reason" 2>&1)
if echo "$OUTPUT" | grep -q "SKIP"; then
    pass_test "skip_test outputs SKIP indicator"
else
    fail_test "skip_test should output SKIP indicator"
fi

# Test 19: test_section outputs section header
OUTPUT=$(source "$HELPERS_FILE" && test_section "Section Name" 2>&1)
if echo "$OUTPUT" | grep -q "Section Name"; then
    pass_test "test_section outputs section name"
else
    fail_test "test_section should output section name"
fi

# --- Test Summary ---
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}FAILED${NC} - Some tests did not pass"
    exit 1
else
    echo "Tests failed: 0"
    echo ""
    echo -e "${GREEN}SUCCESS${NC} - All tests passed!"
    exit 0
fi
