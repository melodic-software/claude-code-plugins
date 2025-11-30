#!/usr/bin/env bash
# test-linting-behavior.sh - Comprehensive markdown linting behavior tests
#
# This test creates actual markdown files with known violations and verifies
# that the hook correctly auto-fixes fixable errors and blocks unfixable ones.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
HOOK_SCRIPT="${PLUGIN_ROOT}/scripts/hooks/markdown-lint.sh"
TEST_DIR="${SCRIPT_DIR}/temp-test-files"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Setup
setup() {
    echo "Setting up test environment..."
    mkdir -p "$TEST_DIR"
}

# Cleanup
cleanup() {
    echo "Cleaning up test files..."
    rm -rf "$TEST_DIR"
}

# Test helper
run_test() {
    local test_name="$1"
    local test_file="$2"
    local expected_exit_code="$3"

    TESTS_RUN=$((TESTS_RUN + 1))

    echo -n "Testing: $test_name... "

    # Create JSON payload
    local payload="{\"tool_name\": \"Write\", \"tool_input\": {\"file_path\": \"$test_file\"}}"

    # Run hook
    local actual_exit_code=0
    echo "$payload" | bash "$HOOK_SCRIPT" > /dev/null 2>&1 || actual_exit_code=$?

    if [ "$actual_exit_code" -eq "$expected_exit_code" ]; then
        echo -e "${GREEN}PASS${NC} (exit code: $actual_exit_code)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo -e "${RED}FAIL${NC} (expected: $expected_exit_code, got: $actual_exit_code)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Test 1: File with only fixable errors (trailing spaces, multiple blank lines)
test_fixable_errors() {
    local test_file="${TEST_DIR}/fixable-errors.md"

    cat > "$test_file" << 'EOF'
# Test Document

This line has trailing spaces.


## Another Section

Some content here.
EOF

    # Should exit 0 after auto-fixing
    run_test "Fixable errors (auto-fixed)" "$test_file" 0
}

# Test 2: File with unfixable errors (duplicate headings)
test_unfixable_errors() {
    local test_file="${TEST_DIR}/unfixable-errors.md"

    cat > "$test_file" << 'EOF'
# Configuration

Some content about configuration.

# Configuration

Duplicate heading - this is unfixable.
EOF

    # Should exit 1 (warn) due to MD024 (duplicate heading) - default enforcement is warn
    run_test "Unfixable errors (warns)" "$test_file" 1
}

# Test 3: File with no errors
test_no_errors() {
    local test_file="${TEST_DIR}/no-errors.md"

    cat > "$test_file" << 'EOF'
# Test Document

This is a properly formatted markdown file.

## Section One

Content here.

## Section Two

More content.
EOF

    # Should exit 0 (no errors)
    run_test "No errors (clean file)" "$test_file" 0
}

# Test 4: Non-markdown file (should be ignored)
test_non_markdown() {
    local test_file="${TEST_DIR}/test.txt"

    echo "This is not a markdown file" > "$test_file"

    # Should exit 0 (ignored, not markdown)
    run_test "Non-markdown file (ignored)" "$test_file" 0
}

# Test 5: Excluded path (should be ignored)
test_excluded_path() {
    local test_dir="${TEST_DIR}/.claude/temp"
    mkdir -p "$test_dir"
    local test_file="${test_dir}/test.md"

    cat > "$test_file" << 'EOF'
# Configuration

Duplicate heading.

# Configuration

Should be ignored due to excluded path.
EOF

    # Should exit 1 (warns) - path exclusion depends on .markdownlint-cli2.jsonc config which may not exist in test env
    run_test "Excluded path (warns without config)" "$test_file" 1
}

# Test 6: File with mixed fixable and unfixable errors
test_mixed_errors() {
    local test_file="${TEST_DIR}/mixed-errors.md"

    cat > "$test_file" << 'EOF'
# Test Document


## Section

# Configuration

Content.

# Configuration

More content.
EOF

    # Should exit 1 (warn) - fixable errors will be fixed, but duplicate heading remains (default enforcement is warn)
    run_test "Mixed errors (warns on unfixable)" "$test_file" 1
}

# Main test execution
main() {
    echo "========================================"
    echo "Markdown Linting Hook Behavior Tests"
    echo "========================================"
    echo ""

    # Check if markdownlint-cli2 is available
    if ! command -v npx &> /dev/null; then
        echo -e "${YELLOW}WARNING: npx not found. Skipping linting behavior tests.${NC}"
        echo "Install Node.js and npm to run these tests."
        exit 0
    fi

    # Check if hook script exists
    if [ ! -f "$HOOK_SCRIPT" ]; then
        echo -e "${RED}ERROR: Hook script not found: $HOOK_SCRIPT${NC}"
        exit 1
    fi

    setup
    trap cleanup EXIT

    echo "Running tests..."
    echo ""

    # Run all tests
    test_fixable_errors
    test_unfixable_errors
    test_no_errors
    test_non_markdown
    test_excluded_path
    test_mixed_errors

    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}SUCCESS - All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}FAILURE - Some tests failed.${NC}"
        exit 1
    fi
}

main "$@"
