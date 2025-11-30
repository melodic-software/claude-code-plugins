#!/usr/bin/env bash
# integration.test.sh - Integration tests for log-hook-events
#
# Tests logging functionality for all 10 Claude Code hook events

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${HOOK_DIR}/../shared/test-helpers.sh"

# Local helper for directory checks
assert_dir_exists() {
    local dir_path="$1"
    local description="${2:-Directory exists check}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -d "$dir_path" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo "  Directory not found: $dir_path"
        return 1
    fi
}

# Local helper for pass_test
pass_test() {
    local description="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: $description"
}

# Local helper for fail_test
fail_test() {
    local description="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: $description"
}

test_suite_start "log-hook-events Integration Tests"

# Test: Hook setup verification
test_section "Hook Setup"
assert_file_exists "${HOOK_DIR}/bash/logging-utils.sh" "Logging utils exist"
assert_file_exists "${HOOK_DIR}/config.yaml" "Hook configuration exists"
assert_file_exists "${HOOK_DIR}/hook.yaml" "Hook metadata exists"

# Test: All 10 event scripts exist
test_section "Event Scripts"
assert_file_exists "${HOOK_DIR}/bash/log-pretooluse.sh" "PreToolUse script exists"
assert_file_exists "${HOOK_DIR}/bash/log-permissionrequest.sh" "PermissionRequest script exists"
assert_file_exists "${HOOK_DIR}/bash/log-posttooluse.sh" "PostToolUse script exists"
assert_file_exists "${HOOK_DIR}/bash/log-notification.sh" "Notification script exists"
assert_file_exists "${HOOK_DIR}/bash/log-userpromptsubmit.sh" "UserPromptSubmit script exists"
assert_file_exists "${HOOK_DIR}/bash/log-stop.sh" "Stop script exists"
assert_file_exists "${HOOK_DIR}/bash/log-subagentstop.sh" "SubagentStop script exists"
assert_file_exists "${HOOK_DIR}/bash/log-precompact.sh" "PreCompact script exists"
assert_file_exists "${HOOK_DIR}/bash/log-sessionstart.sh" "SessionStart script exists"
assert_file_exists "${HOOK_DIR}/bash/log-sessionend.sh" "SessionEnd script exists"

# Test: Log directories exist
test_section "Log Directories"
assert_dir_exists "${HOOK_DIR}/logs/pretooluse" "PreToolUse log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/permissionrequest" "PermissionRequest log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/posttooluse" "PostToolUse log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/notification" "Notification log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/userpromptsubmit" "UserPromptSubmit log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/stop" "Stop log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/subagentstop" "SubagentStop log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/precompact" "PreCompact log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/sessionstart" "SessionStart log directory exists"
assert_dir_exists "${HOOK_DIR}/logs/sessionend" "SessionEnd log directory exists"

# Test: Hook execution with test payload
test_section "Hook Execution"

# Create test payload
TEST_PAYLOAD='{"session_id":"test123","transcript_path":"/test/path.jsonl","cwd":"/workspace","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"test.txt"}}'

# Test PreToolUse logging
echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "PreToolUse hook executed successfully"
else
    fail_test "PreToolUse hook failed with exit code $EXIT_CODE"
fi

# Test: Log file creation
test_section "Log File Creation"

# Get today's date for log file name
TODAY=$(date -u +"%Y-%m-%d")
LOG_FILE="${HOOK_DIR}/logs/pretooluse/${TODAY}.jsonl"

if [ -f "$LOG_FILE" ]; then
    pass_test "Log file created: $LOG_FILE"
    
    # Test: Log file is valid JSONL
    if command -v jq &> /dev/null; then
        if jq -e . "$LOG_FILE" > /dev/null 2>&1; then
            pass_test "Log file contains valid JSON"
        else
            fail_test "Log file contains invalid JSON"
        fi
        
        # Test: Log entry has required fields
        REQUIRED_FIELDS=$(jq 'has("timestamp") and has("event") and has("stdin") and has("stdout") and has("exit_code") and has("duration_ms")' "$LOG_FILE" | tail -1)
        if [ "$REQUIRED_FIELDS" = "true" ]; then
            pass_test "Log entry has all required fields"
        else
            fail_test "Log entry missing required fields"
        fi
        
        # Test: Event name is correct
        EVENT_NAME=$(jq -r '.event' "$LOG_FILE" | tail -1)
        if [ "$EVENT_NAME" = "pretooluse" ]; then
            pass_test "Event name is correct"
        else
            fail_test "Event name is incorrect: $EVENT_NAME"
        fi
    else
        skip_test "jq not available - skipping JSON validation"
    fi
else
    fail_test "Log file not created: $LOG_FILE"
fi

# Test: Configuration enable/disable
test_section "Configuration Control"

# Save original config
ORIGINAL_CONFIG=$(cat "${HOOK_DIR}/config.yaml")

# Test: Disable logging
echo "enabled: false
events:
  pretooluse:
    enabled: true" > "${HOOK_DIR}/config.yaml"

echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook exits successfully when globally disabled"
else
    fail_test "Hook failed when globally disabled (exit code: $EXIT_CODE)"
fi

# Test: Disable specific event
echo "enabled: true
events:
  pretooluse:
    enabled: false" > "${HOOK_DIR}/config.yaml"

echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook exits successfully when event disabled"
else
    fail_test "Hook failed when event disabled (exit code: $EXIT_CODE)"
fi

# Restore original config
echo "$ORIGINAL_CONFIG" > "${HOOK_DIR}/config.yaml"

# Test: Cleanup
test_section "Cleanup"
# Remove test log file
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
    pass_test "Test log file cleaned up"
fi

test_suite_end

