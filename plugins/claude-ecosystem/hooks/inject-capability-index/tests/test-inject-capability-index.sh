#!/usr/bin/env bash
# test-inject-capability-index.sh - Unit tests for inject-capability-index hook
#
# Cross-platform test script for Windows (Git Bash/MSYS2), macOS, and Linux
#
# Run from repo root:
#   bash plugins/claude-ecosystem/hooks/inject-capability-index/tests/test-inject-capability-index.sh
#
# Or with MSYS path conversion disabled (Windows):
#   MSYS_NO_PATHCONV=1 bash plugins/claude-ecosystem/hooks/inject-capability-index/tests/test-inject-capability-index.sh

# Disable MSYS path conversion for Windows compatibility
export MSYS_NO_PATHCONV=1

set -euo pipefail

# Resolve script directory (portable across platforms)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(dirname "$SCRIPT_DIR")"
HOOK_SCRIPT="$HOOK_DIR/bash/inject-capability-index.sh"
PYTHON_SCRIPT="$HOOK_DIR/python/generate_index.py"
CACHE_FILE="$HOOK_DIR/cache/capability-index.txt"

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

# Convert MSYS path to Windows path for Python compatibility
# MSYS paths like /d/repos/... need to be D:/repos/... for Windows Python
msys_to_windows() {
    local path="$1"
    if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
        # Convert /d/... to D:/...
        if [[ "$path" =~ ^/([a-zA-Z])(/.*)?$ ]]; then
            local drive="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"
            echo "${drive^^}:${rest}"
            return
        fi
    fi
    echo "$path"
}

# Find plugins directory
find_plugins_dir() {
    local current="$HOOK_DIR"
    for _ in {1..10}; do
        if [[ -d "$current/plugins" ]]; then
            echo "$current/plugins"
            return 0
        fi
        current="$(dirname "$current")"
    done
    return 1
}

PLUGINS_DIR=$(find_plugins_dir) || PLUGINS_DIR=""

echo "Running inject-capability-index hook tests..."
echo "=========================================="
echo "Platform: $(uname -s)"
echo "Shell: $BASH_VERSION"
echo "Python: ${PYTHON:-not found}"
echo "Plugins dir: ${PLUGINS_DIR:-not found}"
echo "=========================================="

# Test 1: Script exists
if [[ -f "$HOOK_SCRIPT" ]]; then
    test_pass "Hook script exists"
else
    test_fail "Hook script does not exist at $HOOK_SCRIPT"
    exit 1
fi

# Test 2: Python generator script exists
if [[ -f "$PYTHON_SCRIPT" ]]; then
    test_pass "Python generator script exists"
else
    test_fail "Python generator script does not exist at $PYTHON_SCRIPT"
fi

# Test 3: Python generator runs without error
if [[ -n "$PYTHON" && -n "$PLUGINS_DIR" ]]; then
    WIN_SCRIPT=$(msys_to_windows "$PYTHON_SCRIPT")
    WIN_PLUGINS=$(msys_to_windows "$PLUGINS_DIR")
    GEN_OUTPUT=$("$PYTHON" "$WIN_SCRIPT" --detail minimal --plugins-dir "$WIN_PLUGINS" --output json 2>&1) && RC=$? || RC=$?
    if [[ $RC -eq 0 ]]; then
        test_pass "Python generator runs successfully"
    else
        test_fail "Python generator exited with code $RC"
    fi

    # Test 4: Generator output is valid JSON
    if echo "$GEN_OUTPUT" | $PYTHON -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        test_pass "Generator output is valid JSON"
    else
        test_fail "Generator output is not valid JSON"
    fi

    # Test 5: Generator output contains stats
    if echo "$GEN_OUTPUT" | grep -q '"skills"'; then
        test_pass "Generator output contains skills count"
    else
        test_fail "Generator output missing skills count"
    fi

    if echo "$GEN_OUTPUT" | grep -q '"agents"'; then
        test_pass "Generator output contains agents count"
    else
        test_fail "Generator output missing agents count"
    fi

    # Test 6: Generator output contains index
    if echo "$GEN_OUTPUT" | grep -q '"index"'; then
        test_pass "Generator output contains index"
    else
        test_fail "Generator output missing index"
    fi
else
    test_skip "Python generator tests (Python or plugins dir not available)"
fi

# Test 7: Test all detail levels
if [[ -n "$PYTHON" && -n "$PLUGINS_DIR" ]]; then
    WIN_SCRIPT=$(msys_to_windows "$PYTHON_SCRIPT")
    WIN_PLUGINS=$(msys_to_windows "$PLUGINS_DIR")
    for DETAIL in minimal standard comprehensive; do
        OUTPUT=$("$PYTHON" "$WIN_SCRIPT" --detail "$DETAIL" --plugins-dir "$WIN_PLUGINS" --output json 2>&1) && RC=$? || RC=$?
        if [[ $RC -eq 0 ]]; then
            test_pass "Generator runs with --detail $DETAIL"
        else
            test_fail "Generator failed with --detail $DETAIL (exit code $RC)"
        fi
    done
else
    test_skip "Detail level tests (Python or plugins dir not available)"
fi

# Test 8: Generate initial cache for static mode tests
if [[ -n "$PYTHON" && -n "$PLUGINS_DIR" ]]; then
    WIN_SCRIPT=$(msys_to_windows "$PYTHON_SCRIPT")
    WIN_PLUGINS=$(msys_to_windows "$PLUGINS_DIR")
    CACHE_CONTENT=$("$PYTHON" "$WIN_SCRIPT" --detail standard --plugins-dir "$WIN_PLUGINS" --output text 2>/dev/null) || true
    if [[ -n "$CACHE_CONTENT" ]]; then
        echo "$CACHE_CONTENT" > "$CACHE_FILE"
        test_pass "Generated cache file for tests"
    else
        test_fail "Failed to generate cache content"
    fi
fi

# Test 9: Hook script runs without error in static mode
export CLAUDE_HOOK_CAPABILITY_INDEX_MODE=static
export CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED=1
unset CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL 2>/dev/null || true
OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
if [[ $RC -eq 0 ]]; then
    test_pass "Hook script exits with code 0 in static mode"
else
    test_fail "Hook script exited with code $RC in static mode"
fi

# Test 10: Output is valid JSON
if [[ -n "$PYTHON" ]]; then
    if echo "$OUTPUT" | $PYTHON -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        test_pass "Hook output is valid JSON"
    else
        test_fail "Hook output is not valid JSON"
    fi
else
    test_skip "Hook JSON validation (Python not available)"
fi

# Test 11: Output contains hookSpecificOutput
if echo "$OUTPUT" | grep -q "hookSpecificOutput"; then
    test_pass "Output contains hookSpecificOutput"
else
    test_fail "Output missing hookSpecificOutput"
fi

# Test 12: Output contains capability-index tag (if cache exists)
if [[ -f "$CACHE_FILE" ]]; then
    if echo "$OUTPUT" | grep -q "capability-index"; then
        test_pass "Output contains capability-index tag"
    else
        test_fail "Output missing capability-index tag"
    fi
else
    test_skip "capability-index tag test (no cache file)"
fi

# Test 13: Hook respects disabled flag
export CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED=0
DISABLED_OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
if [[ $RC -eq 0 ]]; then
    test_pass "Hook exits with code 0 when disabled"
else
    test_fail "Hook exited with code $RC when disabled"
fi

# Test 14: Disabled output does not contain capability content
if echo "$DISABLED_OUTPUT" | grep -q "capability-index"; then
    test_fail "Disabled output should not contain capability index"
else
    test_pass "Disabled output correctly omits capability index"
fi

# Test 15: Disabled output is still valid JSON
if [[ -n "$PYTHON" ]]; then
    if echo "$DISABLED_OUTPUT" | $PYTHON -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        test_pass "Disabled output is valid JSON"
    else
        test_fail "Disabled output is not valid JSON"
    fi
else
    test_skip "Disabled JSON validation (Python not available)"
fi

# Test 16: Test cached mode (regenerates if stale)
if [[ -n "$PYTHON" && -f "$CACHE_FILE" ]]; then
    export CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED=1
    export CLAUDE_HOOK_CAPABILITY_INDEX_MODE=cached
    CACHED_OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
    if [[ $RC -eq 0 ]]; then
        test_pass "Hook runs in cached mode"
    else
        test_fail "Hook failed in cached mode (exit code $RC)"
    fi
else
    test_skip "Cached mode test (Python or cache not available)"
fi

# Test 17: Test dynamic mode
if [[ -n "$PYTHON" && -n "$PLUGINS_DIR" ]]; then
    export CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED=1
    export CLAUDE_HOOK_CAPABILITY_INDEX_MODE=dynamic
    DYNAMIC_OUTPUT=$(echo '{}' | bash "$HOOK_SCRIPT" 2>&1) && RC=$? || RC=$?
    if [[ $RC -eq 0 ]]; then
        test_pass "Hook runs in dynamic mode"
    else
        test_fail "Hook failed in dynamic mode (exit code $RC)"
    fi
else
    test_skip "Dynamic mode test (Python or plugins dir not available)"
fi

# Cleanup
unset CLAUDE_HOOK_CAPABILITY_INDEX_ENABLED 2>/dev/null || true
unset CLAUDE_HOOK_CAPABILITY_INDEX_MODE 2>/dev/null || true
unset CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL 2>/dev/null || true

echo "=========================================="
TOTAL=$((PASSED + FAILED + SKIPPED))
echo -e "Results: ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC} (total: $TOTAL)"

if [[ $FAILED -gt 0 ]]; then
    echo "Some tests failed!"
    exit 1
fi

echo "All tests passed!"
exit 0
