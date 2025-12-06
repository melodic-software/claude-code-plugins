#!/usr/bin/env bash
# test-inject-best-practices.sh - Unit tests for inject-best-practices hook
#
# Cross-platform test script for Windows (Git Bash/MSYS2), macOS, and Linux
#
# Run from repo root:
#   bash plugins/claude-ecosystem/hooks/inject-best-practices/tests/test-inject-best-practices.sh
#
# Or with MSYS path conversion disabled (Windows):
#   MSYS_NO_PATHCONV=1 bash plugins/claude-ecosystem/hooks/inject-best-practices/tests/test-inject-best-practices.sh

# Disable MSYS path conversion for Windows compatibility
export MSYS_NO_PATHCONV=1

set -euo pipefail

# Resolve script directory (portable across platforms)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../bash/inject-best-practices.sh"

# Colors for output (with fallback for non-color terminals)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

PASSED=0
FAILED=0
SKIPPED=0

test_pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((PASSED++)) || true
}

test_fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((FAILED++)) || true
}

test_skip() {
    echo -e "${YELLOW}SKIP${NC}: $1"
    ((SKIPPED++)) || true
}

# Find Python interpreter (python3 or python)
find_python() {
    if command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null; then
        echo "python"
    else
        echo ""
    fi
}

PYTHON=$(find_python)

echo "Running inject-best-practices hook tests..."
echo "=========================================="
echo "Platform: $(uname -s)"
echo "Shell: $BASH_VERSION"
echo "Python: ${PYTHON:-not found}"
echo "=========================================="

# Test 1: Script exists
if [[ -f "$HOOK_SCRIPT" ]]; then
    test_pass "Hook script exists"
else
    test_fail "Hook script does not exist at $HOOK_SCRIPT"
    exit 1
fi

# Test 2: Script runs without error when enabled (default)
unset CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED 2>/dev/null || true
OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
if [[ $RC -eq 0 ]]; then
    test_pass "Script exits with code 0 when enabled"
else
    test_fail "Script exited with code $RC when enabled"
fi

# Test 3: Output is valid JSON
if [[ -n "$PYTHON" ]]; then
    if echo "$OUTPUT" | $PYTHON -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        test_pass "Output is valid JSON"
    else
        test_fail "Output is not valid JSON"
    fi
else
    test_skip "JSON validation (Python not available)"
fi

# Test 4: Output contains hookSpecificOutput
if echo "$OUTPUT" | grep -q "hookSpecificOutput"; then
    test_pass "Output contains hookSpecificOutput"
else
    test_fail "Output missing hookSpecificOutput"
fi

# Test 5: Output contains additionalContext with content
if echo "$OUTPUT" | grep -q "additionalContext"; then
    test_pass "Output contains additionalContext"
else
    test_fail "Output missing additionalContext"
fi

# Test 6: Output contains best-practices-reminder tag
if echo "$OUTPUT" | grep -q "best-practices-reminder"; then
    test_pass "Output contains best-practices-reminder tag"
else
    test_fail "Output missing best-practices-reminder tag"
fi

# Test 7: Output contains key rule categories
if echo "$OUTPUT" | grep -q "Skills-First"; then
    test_pass "Output contains Skills-First rule"
else
    test_fail "Output missing Skills-First rule"
fi

if echo "$OUTPUT" | grep -q "Progressive Disclosure"; then
    test_pass "Output contains Progressive Disclosure rule"
else
    test_fail "Output missing Progressive Disclosure rule"
fi

if echo "$OUTPUT" | grep -q "Zero Complacency"; then
    test_pass "Output contains Zero Complacency rule"
else
    test_fail "Output missing Zero Complacency rule"
fi

if echo "$OUTPUT" | grep -q "docs-management"; then
    test_pass "Output contains docs-management reference"
else
    test_fail "Output missing docs-management reference"
fi

# Test 8: Output contains Opus 4.5 precision note (new enhancement)
if echo "$OUTPUT" | grep -q "Opus 4.5"; then
    test_pass "Output contains Opus 4.5 precision note"
else
    test_fail "Output missing Opus 4.5 precision note"
fi

# Test 9: Output contains MCP permissions warning (new enhancement)
if echo "$OUTPUT" | grep -q "MCP Permissions"; then
    test_pass "Output contains MCP permissions warning"
else
    test_fail "Output missing MCP permissions warning"
fi

# Test 10: Script respects disabled flag
export CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED=0
DISABLED_OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
if [[ $RC -eq 0 ]]; then
    test_pass "Script exits with code 0 when disabled"
else
    test_fail "Script exited with code $RC when disabled"
fi

# Test 11: Disabled output does not contain additionalContext content
if echo "$DISABLED_OUTPUT" | grep -q "best-practices-reminder"; then
    test_fail "Disabled output should not contain reminder content"
else
    test_pass "Disabled output correctly omits reminder content"
fi

# Test 12: Disabled output is still valid JSON
if [[ -n "$PYTHON" ]]; then
    if echo "$DISABLED_OUTPUT" | $PYTHON -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        test_pass "Disabled output is valid JSON"
    else
        test_fail "Disabled output is not valid JSON"
    fi
else
    test_skip "Disabled JSON validation (Python not available)"
fi

# Test 13: Disabled output has correct structure
if echo "$DISABLED_OUTPUT" | grep -q '"hookEventName":"SessionStart"'; then
    test_pass "Disabled output has correct hookEventName"
else
    test_fail "Disabled output missing hookEventName"
fi

# Cleanup
unset CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED 2>/dev/null || true

echo "=========================================="
TOTAL=$((PASSED + FAILED + SKIPPED))
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC} (total: $TOTAL)"

if [[ $FAILED -gt 0 ]]; then
    echo "Some tests failed!"
    exit 1
fi

echo "All tests passed!"
exit 0
