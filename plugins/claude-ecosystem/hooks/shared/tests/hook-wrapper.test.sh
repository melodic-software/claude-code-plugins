#!/usr/bin/env bash
# hook-wrapper.test.sh - Tests for hook-wrapper.sh Windows path normalization
#
# Tests the wrapper script that normalizes CLAUDE_PLUGIN_ROOT paths for Windows compatibility.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${SCRIPT_DIR}/../hook-wrapper.sh"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Test counters
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

skip_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}⊙${NC} SKIP: $1"
}

echo ""
echo "=========================================="
echo "Test Suite: hook-wrapper.sh (claude-ecosystem)"
echo "=========================================="
echo ""

# --- Test Section: Wrapper Setup ---
echo "--- Wrapper Setup ---"

# Test 1: Wrapper script exists
if [ -f "$WRAPPER" ]; then
    pass_test "Wrapper script exists"
else
    fail_test "Wrapper script not found at $WRAPPER"
fi

# Test 2: Wrapper is a bash script
if head -1 "$WRAPPER" | grep -q "#!/usr/bin/env bash"; then
    pass_test "Wrapper has correct shebang"
else
    fail_test "Wrapper missing or incorrect shebang"
fi

# --- Test Section: Error Handling ---
echo ""
echo "--- Error Handling ---"

# Test 3: Wrapper requires argument
OUTPUT=$(bash "$WRAPPER" 2>&1) || true
if echo "$OUTPUT" | grep -q "Usage:"; then
    pass_test "Wrapper shows usage when no arguments"
else
    fail_test "Wrapper should show usage when no arguments"
fi

# Test 4: Wrapper handles missing script gracefully
OUTPUT=$(bash "$WRAPPER" /nonexistent/script.sh 2>&1) || true
if echo "$OUTPUT" | grep -q "not found"; then
    pass_test "Wrapper reports missing scripts"
else
    fail_test "Wrapper should report missing scripts"
fi

# --- Test Section: Script Execution ---
echo ""
echo "--- Script Execution ---"

# Test 5: Wrapper can execute a real hook script
TARGET_SCRIPT="/hooks/inject-current-date/bash/inject-current-date.sh"
if [ -f "${PLUGIN_ROOT}${TARGET_SCRIPT}" ]; then
    # Create minimal test payload
    TEST_PAYLOAD='{}'

    # Execute through wrapper
    OUTPUT=$(echo "$TEST_PAYLOAD" | bash "$WRAPPER" "$TARGET_SCRIPT" 2>&1) || EXIT_CODE=$?
    EXIT_CODE=${EXIT_CODE:-0}

    if [ $EXIT_CODE -eq 0 ]; then
        pass_test "Wrapper successfully executes target script"
    else
        fail_test "Wrapper failed to execute target script (exit code: $EXIT_CODE)"
    fi
else
    skip_test "Target script not found: ${PLUGIN_ROOT}${TARGET_SCRIPT}"
fi

# Test 6: Wrapper preserves exit codes
# Create a temp script that exits with code 42
TEMP_SCRIPT=$(mktemp)
echo '#!/usr/bin/env bash' > "$TEMP_SCRIPT"
echo 'exit 42' >> "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# Get relative path from plugin root
TEMP_RELATIVE="/$(basename "$TEMP_SCRIPT")"
cp "$TEMP_SCRIPT" "${PLUGIN_ROOT}${TEMP_RELATIVE}"

bash "$WRAPPER" "$TEMP_RELATIVE" 2>/dev/null || EXIT_CODE=$?
rm -f "$TEMP_SCRIPT" "${PLUGIN_ROOT}${TEMP_RELATIVE}"

if [ "${EXIT_CODE:-0}" -eq 42 ]; then
    pass_test "Wrapper preserves exit codes"
else
    fail_test "Wrapper should preserve exit codes (expected 42, got ${EXIT_CODE:-0})"
fi

# Test 7: Wrapper passes stdin to target script
# Create a temp script that reads and echoes stdin
TEMP_SCRIPT=$(mktemp)
echo '#!/usr/bin/env bash' > "$TEMP_SCRIPT"
echo 'cat' >> "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

TEMP_RELATIVE="/$(basename "$TEMP_SCRIPT")"
cp "$TEMP_SCRIPT" "${PLUGIN_ROOT}${TEMP_RELATIVE}"

OUTPUT=$(echo "test-input-data" | bash "$WRAPPER" "$TEMP_RELATIVE" 2>/dev/null) || true
rm -f "$TEMP_SCRIPT" "${PLUGIN_ROOT}${TEMP_RELATIVE}"

if echo "$OUTPUT" | grep -q "test-input-data"; then
    pass_test "Wrapper passes stdin to target script"
else
    fail_test "Wrapper should pass stdin to target script"
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
