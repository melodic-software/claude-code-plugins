#!/usr/bin/env bash
# test-helpers.sh - Test framework utilities for Claude Code hooks
#
# Provides assertion functions and test utilities for bash-based testing.
#
# Usage: Source this file in your test script: source "path/to/test-helpers.sh"

set -euo pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# Assert that two values are equal
# Usage: assert_equals "expected" "actual" "test description"
assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="${3:-Equality check}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

# Assert that exit code matches expected
# Usage: assert_exit_code 0 $? "command should succeed"
assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local description="${3:-Exit code check}"
    
    assert_equals "$expected" "$actual" "$description"
}

# Assert that string contains substring
# Usage: assert_contains "full string" "substring" "test description"
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local description="${3:-Contains check}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo "  Haystack: $haystack"
        echo "  Needle:   $needle"
        return 1
    fi
}

# Assert that string does NOT contain substring
# Usage: assert_not_contains "full string" "substring" "test description"
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local description="${3:-Not contains check}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$haystack" != *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo "  Haystack: $haystack"
        echo "  Should not contain: $needle"
        return 1
    fi
}

# Assert that file exists
# Usage: assert_file_exists "/path/to/file" "test description"
assert_file_exists() {
    local file_path="$1"
    local description="${2:-File exists check}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -f "$file_path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo "  File not found: $file_path"
        return 1
    fi
}

# Assert that file does not exist
# Usage: assert_file_not_exists "/path/to/file" "test description"
assert_file_not_exists() {
    local file_path="$1"
    local description="${2:-File not exists check}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ ! -f "$file_path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo "  File should not exist: $file_path"
        return 1
    fi
}

# Run a command and capture output and exit code
# Usage: run_command "command to run"
# Sets: COMMAND_OUTPUT, COMMAND_EXIT_CODE
run_command() {
    local command="$1"
    COMMAND_OUTPUT=$(eval "$command" 2>&1) || COMMAND_EXIT_CODE=$?
    COMMAND_EXIT_CODE=${COMMAND_EXIT_CODE:-0}
}

# Print test suite header
# Usage: test_suite_start "Test Suite Name"
test_suite_start() {
    local suite_name="$1"
    echo ""
    echo "=========================================="
    echo "Test Suite: $suite_name"
    echo "=========================================="
    echo ""
}

# Print test suite summary
# Usage: test_suite_end
test_suite_end() {
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
        return 1
    else
        echo "Tests failed: 0"
        echo ""
        echo -e "${GREEN}SUCCESS${NC} - All tests passed!"
        return 0
    fi
}

# Skip a test with a message
# Usage: skip_test "Reason for skipping"
skip_test() {
    local reason="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}⊙${NC} SKIP: $reason"
}

# Print test section header
# Usage: test_section "Section Name"
test_section() {
    local section_name="$1"
    echo ""
    echo "--- $section_name ---"
}

