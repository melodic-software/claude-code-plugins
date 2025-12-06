#!/usr/bin/env bash
# integration.test.sh - Tests for check-principles.sh architecture compliance hook
#
# Tests the hook that provides lightweight architecture compliance checking.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/../check-principles.sh"
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
echo "Test Suite: check-principles.sh"
echo "=========================================="
echo ""

# --- Test Section: Script Setup ---
echo "--- Script Setup ---"

# Test 1: Hook script exists
if [ -f "$HOOK_SCRIPT" ]; then
    pass_test "Hook script exists"
else
    fail_test "Hook script not found at $HOOK_SCRIPT"
fi

# Test 2: Hook is a bash script
if head -1 "$HOOK_SCRIPT" | grep -q "#!/usr/bin/env bash"; then
    pass_test "Hook has correct shebang"
else
    fail_test "Hook missing or incorrect shebang"
fi

# Test 3: Hook uses strict mode
if grep -q "set -euo pipefail" "$HOOK_SCRIPT"; then
    pass_test "Hook uses strict mode (set -euo pipefail)"
else
    fail_test "Hook should use strict mode"
fi

# --- Test Section: Disabled by Default ---
echo ""
echo "--- Disabled by Default ---"

# Test 4: Hook exits early when disabled (default)
OUTPUT=$(echo '{}' | ENABLED=false bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ] && [ -z "$OUTPUT" ]; then
    pass_test "Hook exits silently when disabled"
else
    fail_test "Hook should exit silently when disabled (exit code: $EXIT_CODE, output: $OUTPUT)"
fi

# Test 5: Hook exits early with no ENABLED var
OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook exits cleanly with no ENABLED variable"
else
    fail_test "Hook should exit cleanly with no ENABLED variable"
fi

# --- Test Section: ENABLED Value Variants ---
echo ""
echo "--- ENABLED Value Variants ---"

# Test 6: Hook accepts ENABLED=TRUE (uppercase)
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
mkdir -p architecture
echo "# Principles" > architecture/principles.md

OUTPUT=$(echo '{}' | ENABLED=TRUE bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "compliance"; then
    pass_test "Hook accepts ENABLED=TRUE (uppercase)"
else
    fail_test "Hook should accept ENABLED=TRUE (exit: $EXIT_CODE, output: $OUTPUT)"
fi

cd - > /dev/null
rm -rf "$TEMP_DIR"

# Test 7: Hook accepts ENABLED=True (mixed case)
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
mkdir -p architecture
echo "# Principles" > architecture/principles.md

OUTPUT=$(echo '{}' | ENABLED=True bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "compliance"; then
    pass_test "Hook accepts ENABLED=True (mixed case)"
else
    fail_test "Hook should accept ENABLED=True (exit: $EXIT_CODE, output: $OUTPUT)"
fi

cd - > /dev/null
rm -rf "$TEMP_DIR"

# Test 8: Hook accepts ENABLED=1
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
mkdir -p architecture
echo "# Principles" > architecture/principles.md

OUTPUT=$(echo '{}' | ENABLED=1 bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "compliance"; then
    pass_test "Hook accepts ENABLED=1"
else
    fail_test "Hook should accept ENABLED=1 (exit: $EXIT_CODE, output: $OUTPUT)"
fi

cd - > /dev/null
rm -rf "$TEMP_DIR"

# Test 9: Hook accepts ENABLED=yes
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
mkdir -p architecture
echo "# Principles" > architecture/principles.md

OUTPUT=$(echo '{}' | ENABLED=yes bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "compliance"; then
    pass_test "Hook accepts ENABLED=yes"
else
    fail_test "Hook should accept ENABLED=yes (exit: $EXIT_CODE, output: $OUTPUT)"
fi

cd - > /dev/null
rm -rf "$TEMP_DIR"

# Test 10: Hook accepts ENABLED=YES (uppercase)
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
mkdir -p architecture
echo "# Principles" > architecture/principles.md

OUTPUT=$(echo '{}' | ENABLED=YES bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "compliance"; then
    pass_test "Hook accepts ENABLED=YES (uppercase)"
else
    fail_test "Hook should accept ENABLED=YES (exit: $EXIT_CODE, output: $OUTPUT)"
fi

cd - > /dev/null
rm -rf "$TEMP_DIR"

# --- Test Section: Enabled Behavior ---
echo ""
echo "--- Enabled Behavior ---"

# Test 11: Hook requires principles file when enabled
# Create temp directory structure
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

OUTPUT=$(echo '{}' | ENABLED=true bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook handles missing principles file gracefully"
else
    fail_test "Hook should handle missing principles file gracefully"
fi

# Test 12: Hook outputs message when principles file exists
mkdir -p architecture
echo "# Architecture Principles" > architecture/principles.md

OUTPUT=$(echo '{}' | ENABLED=true bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "compliance"; then
    pass_test "Hook outputs compliance message when enabled with principles"
else
    fail_test "Hook should output compliance message (exit: $EXIT_CODE, output: $OUTPUT)"
fi

# Test 13: Hook mentions the command for comprehensive review
if echo "$OUTPUT" | grep -q "architecture-review"; then
    pass_test "Hook references architecture-review command"
else
    fail_test "Hook should reference architecture-review command"
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"

# --- Test Section: Input Handling ---
echo ""
echo "--- Input Handling ---"

# Test 14: Hook consumes stdin
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"
mkdir -p architecture
echo "# Principles" > architecture/principles.md

# Provide JSON input via stdin
TOOL_RESULT='{"tool": "Edit", "file": "test.ts"}'
OUTPUT=$(echo "$TOOL_RESULT" | ENABLED=true bash "$HOOK_SCRIPT" 2>&1) || EXIT_CODE=$?
EXIT_CODE=${EXIT_CODE:-0}

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook accepts JSON input via stdin"
else
    fail_test "Hook should accept JSON input via stdin"
fi

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"

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
