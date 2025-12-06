#!/usr/bin/env bash
# test-inject-best-practices.sh - Unit tests for inject-best-practices hook
#
# Run: bash plugins/claude-ecosystem/hooks/inject-best-practices/tests/test-inject-best-practices.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../bash/inject-best-practices.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

test_pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((FAILED++))
}

echo "Running inject-best-practices hook tests..."
echo "=========================================="

# Test 1: Script exists and is executable concept (we'll make it executable)
if [[ -f "$HOOK_SCRIPT" ]]; then
    test_pass "Hook script exists"
else
    test_fail "Hook script does not exist at $HOOK_SCRIPT"
    exit 1
fi

# Test 2: Script runs without error when enabled (default)
unset CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED
OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
if [[ $RC -eq 0 ]]; then
    test_pass "Script exits with code 0 when enabled"
else
    test_fail "Script exited with code $RC when enabled"
fi

# Test 3: Output is valid JSON
if echo "$OUTPUT" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
    test_pass "Output is valid JSON"
else
    test_fail "Output is not valid JSON: $OUTPUT"
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

# Test 8: Script respects disabled flag
export CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED=0
DISABLED_OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
if [[ $RC -eq 0 ]]; then
    test_pass "Script exits with code 0 when disabled"
else
    test_fail "Script exited with code $RC when disabled"
fi

# Test 9: Disabled output does not contain additionalContext content
if echo "$DISABLED_OUTPUT" | grep -q "best-practices-reminder"; then
    test_fail "Disabled output should not contain reminder content"
else
    test_pass "Disabled output correctly omits reminder content"
fi

# Test 10: Disabled output is still valid JSON
if echo "$DISABLED_OUTPUT" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
    test_pass "Disabled output is valid JSON"
else
    test_fail "Disabled output is not valid JSON: $DISABLED_OUTPUT"
fi

unset CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED

echo "=========================================="
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi

echo "All tests passed!"
exit 0
