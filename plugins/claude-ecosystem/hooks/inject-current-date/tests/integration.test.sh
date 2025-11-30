#!/usr/bin/env bash
# integration.test.sh - Integration tests for inject-current-date hook
#
# Tests the SessionStart hook that automatically injects the current
# UTC date/time into Claude's context at session start.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${HOOK_DIR}/../shared/test-helpers.sh"

# Find jq - rely on PATH, skip tests gracefully if not found
find_jq() {
    command -v jq 2>/dev/null || return 1
}

JQ_CMD=$(find_jq || echo "")

# Helper function to run hook and capture output
run_hook() {
    local input="${1:-{}}"
    echo "$input" | bash "${HOOK_DIR}/bash/inject-current-date.sh" 2>/dev/null
}

# Helper function to check if output contains additionalContext
has_context_injection() {
    local output="$1"
    [[ "$output" == *"additionalContext"* ]]
}

test_suite_start "inject-current-date Integration Tests"

# ============================================================================
# SECTION 1: Hook Setup
# ============================================================================
test_section "Hook Setup"

assert_file_exists "${HOOK_DIR}/bash/inject-current-date.sh" "Hook script exists"
assert_file_exists "${HOOK_DIR}/config.yaml" "Hook config.yaml exists"
assert_file_exists "${HOOK_DIR}/hook.yaml" "Hook hook.yaml exists"
assert_file_exists "${HOOK_DIR}/README.md" "Hook README.md exists"

# ============================================================================
# SECTION 2: Hook Output Structure
# ============================================================================
test_section "Hook Output Structure"

OUTPUT=$(run_hook '{}')

# Verify output exists and is not empty
if [[ -n "$OUTPUT" ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Hook produces output"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Hook should produce output"
fi

# Verify context injection
if has_context_injection "$OUTPUT"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Output contains additionalContext"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Output should contain additionalContext"
    echo "  Output: $OUTPUT"
fi

# Verify hookSpecificOutput structure
assert_contains "$OUTPUT" "hookSpecificOutput" "Contains hookSpecificOutput wrapper"
assert_contains "$OUTPUT" "SessionStart" "Contains SessionStart event name"

# ============================================================================
# SECTION 3: Date Content Verification
# ============================================================================
test_section "Date Content Verification"

OUTPUT=$(run_hook '{}')

# Verify UTC date format (YYYY-MM-DD HH:MM:SS UTC)
if [[ "$OUTPUT" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\ UTC ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Contains UTC date format (YYYY-MM-DD HH:MM:SS UTC)"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should contain UTC date format"
    echo "  Output: $OUTPUT"
fi

# Verify ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ)
if [[ "$OUTPUT" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Contains ISO 8601 date format"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should contain ISO 8601 date format"
    echo "  Output: $OUTPUT"
fi

# Verify session-context tags
assert_contains "$OUTPUT" "session-context" "Contains session-context tags"
assert_contains "$OUTPUT" "CURRENT DATE/TIME" "Contains date/time header"

# ============================================================================
# SECTION 4: Exit Code Verification (Always 0)
# ============================================================================
test_section "Exit Code Verification"

# Hook should always exit 0 (never blocks session)
echo '{}' | bash "${HOOK_DIR}/bash/inject-current-date.sh" &>/dev/null
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Hook exits 0 with empty JSON"

echo '' | bash "${HOOK_DIR}/bash/inject-current-date.sh" &>/dev/null
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Hook exits 0 with empty input"

echo '{"session_id": "test-123"}' | bash "${HOOK_DIR}/bash/inject-current-date.sh" &>/dev/null
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Hook exits 0 with session data"

# ============================================================================
# SECTION 5: JSON Output Validation
# ============================================================================
test_section "JSON Output Validation"

OUTPUT=$(run_hook '{}')

# Verify valid JSON output
if [[ -n "$JQ_CMD" ]]; then
    if echo "$OUTPUT" | "$JQ_CMD" empty 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: Output is valid JSON"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: Output is not valid JSON"
        echo "  Output: $OUTPUT"
    fi

    # Verify hookSpecificOutput.hookEventName
    # Strip CR characters (Windows jq.exe may output CRLF)
    HOOK_EVENT=$(echo "$OUTPUT" | "$JQ_CMD" -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null | tr -d '\r')
    assert_equals "SessionStart" "$HOOK_EVENT" "hookEventName is SessionStart"

    # Verify additionalContext exists and is non-empty
    CONTEXT=$(echo "$OUTPUT" | "$JQ_CMD" -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    if [[ -n "$CONTEXT" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: additionalContext is non-empty"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: additionalContext should be non-empty"
    fi
else
    skip_test "jq not found - skipping detailed JSON validation"
    
    # Basic JSON structure check without jq
    if [[ "$OUTPUT" == *"{"* && "$OUTPUT" == *"}"* ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: Output has JSON structure (basic check)"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: Output should have JSON structure"
    fi
fi

# ============================================================================
# SECTION 6: Date Accuracy (Basic Check)
# ============================================================================
test_section "Date Accuracy Check"

OUTPUT=$(run_hook '{}')
CURRENT_YEAR=$(date -u +"%Y")
CURRENT_MONTH=$(date -u +"%m")
CURRENT_DAY=$(date -u +"%d")

# Verify the year is current
if [[ "$OUTPUT" == *"$CURRENT_YEAR"* ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Contains current year ($CURRENT_YEAR)"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should contain current year ($CURRENT_YEAR)"
fi

# Verify date includes current date (year-month-day)
CURRENT_DATE="${CURRENT_YEAR}-${CURRENT_MONTH}-${CURRENT_DAY}"
if [[ "$OUTPUT" == *"$CURRENT_DATE"* ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Contains current date ($CURRENT_DATE)"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should contain current date ($CURRENT_DATE)"
fi

# ============================================================================
# SECTION 7: Idempotency (Multiple Runs)
# ============================================================================
test_section "Idempotency"

# Hook should work consistently across multiple invocations
OUTPUT1=$(run_hook '{}')
OUTPUT2=$(run_hook '{}')

# Both outputs should have the same structure
if has_context_injection "$OUTPUT1" && has_context_injection "$OUTPUT2"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Multiple invocations produce consistent structure"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Hook should produce consistent output structure"
fi

# ============================================================================
# SECTION 8: Guidance Content
# ============================================================================
test_section "Guidance Content"

OUTPUT=$(run_hook '{}')

# Verify guidance message is included
assert_contains "$OUTPUT" "session start" "Contains session start mention"
assert_contains "$OUTPUT" "time-sensitive" "Contains time-sensitive guidance"

test_suite_end

