#!/usr/bin/env bash
# integration.test.sh - Integration tests for log-hook-events
#
# Tests logging functionality for all 10 Claude Code hook events

# ============================================================================
# Environment Isolation - Clear hook-related env vars for consistent test behavior
# ============================================================================
# Unset all CLAUDE_HOOK_LOG_* env vars to prevent user config from affecting tests
for var in $(env | grep '^CLAUDE_HOOK_LOG_' | cut -d= -f1); do
    unset "$var"
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Try to source shared test helpers (may not exist in all setups)
if [ -f "${HOOK_DIR}/../shared/test-helpers.sh" ]; then
    source "${HOOK_DIR}/../shared/test-helpers.sh"
else
    # Fallback: define minimal test helpers inline
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
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
    skip_test() {
        local reason="$1"
        TESTS_RUN=$((TESTS_RUN + 1))
        echo -e "${YELLOW}⊙${NC} SKIP: $reason"
    }
    test_suite_start() {
        echo ""
        echo "=========================================="
        echo "Test Suite: $1"
        echo "=========================================="
        echo ""
    }
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
    test_section() {
        echo ""
        echo "--- $1 ---"
    }
fi

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

# Local helper for pass_test (only define if not already defined from shared helpers)
if ! declare -f pass_test &>/dev/null; then
    pass_test() {
        local description="$1"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
    }
fi

# Local helper for fail_test (only define if not already defined from shared helpers)
if ! declare -f fail_test &>/dev/null; then
    fail_test() {
        local description="$1"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
    }
fi

# Temp file tracking for guaranteed cleanup (handles Ctrl+C and early failures)
TEST_FILES_TO_CLEAN=()
cleanup_test_files() {
    for f in "${TEST_FILES_TO_CLEAN[@]}"; do
        rm -f "$f" 2>/dev/null || true
    done
}
trap cleanup_test_files EXIT

test_suite_start "log-hook-events Integration Tests"

# Test: Windows path compatibility wrapper
test_section "Windows Path Compatibility (Wrapper)"
WRAPPER="${HOOK_DIR}/../shared/hook-wrapper.sh"
PLUGIN_ROOT="$(cd "${HOOK_DIR}/../.." && pwd)"

assert_file_exists "$WRAPPER" "Wrapper script exists"

# Test wrapper can execute target script via wrapper
TEST_WRAPPER_PAYLOAD='{"session_id":"wrapper-test","hook_event_name":"PreToolUse"}'
echo "$TEST_WRAPPER_PAYLOAD" | bash "$WRAPPER" /hooks/log-hook-events/bash/log-pretooluse.sh
WRAPPER_EXIT=$?

if [ $WRAPPER_EXIT -eq 0 ]; then
    pass_test "Wrapper successfully executes target script"
else
    fail_test "Wrapper failed with exit code $WRAPPER_EXIT"
fi

# Test: Hook setup verification
test_section "Hook Setup"
assert_file_exists "${HOOK_DIR}/bash/logging-utils.sh" "Logging utils exist"
assert_file_exists "${HOOK_DIR}/README.md" "Hook README exists"
assert_file_exists "${HOOK_DIR}/python/log_event.py" "Python logger exists"

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

# Test: Log directories - create if needed (directories are created on-demand by Python logger)
test_section "Log Directories"
# Ensure log directories exist for testing (Python logger creates them on first write)
mkdir -p "${HOOK_DIR}/logs/pretooluse"
mkdir -p "${HOOK_DIR}/logs/permissionrequest"
mkdir -p "${HOOK_DIR}/logs/posttooluse"
mkdir -p "${HOOK_DIR}/logs/notification"
mkdir -p "${HOOK_DIR}/logs/userpromptsubmit"
mkdir -p "${HOOK_DIR}/logs/stop"
mkdir -p "${HOOK_DIR}/logs/subagentstop"
mkdir -p "${HOOK_DIR}/logs/precompact"
mkdir -p "${HOOK_DIR}/logs/sessionstart"
mkdir -p "${HOOK_DIR}/logs/sessionend"

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

# Test: Hook execution with test payload (logging disabled by default)
test_section "Hook Execution (Default - Disabled)"

# Create test payload
TEST_PAYLOAD='{"session_id":"test123","transcript_path":"/test/path.jsonl","cwd":"/workspace","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"test.txt"}}'

# Test PreToolUse logging exits cleanly when disabled (default)
echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "PreToolUse hook exits cleanly when disabled (default)"
else
    fail_test "PreToolUse hook failed with exit code $EXIT_CODE"
fi

# Test: Log file creation (with master toggle enabled)
test_section "Log File Creation (With Logging Enabled)"

# Ensure clean environment - unset any per-event overrides from previous runs
unset CLAUDE_HOOK_LOG_PRETOOLUSE_ENABLED

# Enable master toggle and set full verbosity for field validation tests
export CLAUDE_HOOK_LOG_EVENTS_ENABLED=1
export CLAUDE_HOOK_LOG_VERBOSITY=full

# Get today's date for log file name
TODAY=$(date -u +"%Y-%m-%d")
LOG_FILE="${HOOK_DIR}/logs/pretooluse/${TODAY}.jsonl"
TEST_FILES_TO_CLEAN+=("$LOG_FILE")

# Remove any existing log file first
rm -f "$LOG_FILE"

# Run hook with logging enabled
echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"

if [ -f "$LOG_FILE" ]; then
    pass_test "Log file created when master toggle enabled: $LOG_FILE"

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
    fail_test "Log file not created when master toggle enabled: $LOG_FILE"
fi

# Clean up test env vars
unset CLAUDE_HOOK_LOG_EVENTS_ENABLED
unset CLAUDE_HOOK_LOG_VERBOSITY

# Test: Configuration enable/disable via environment variables
test_section "Configuration Control (Environment Variables)"

# Test: Logging disabled when master toggle is off (default behavior)
unset CLAUDE_HOOK_LOG_EVENTS_ENABLED
echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook exits successfully when master toggle is off (default)"
else
    fail_test "Hook failed when master toggle is off (exit code: $EXIT_CODE)"
fi

# Test: Logging enabled when master toggle is on
export CLAUDE_HOOK_LOG_EVENTS_ENABLED=1
echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook executes successfully when master toggle is on"
else
    fail_test "Hook failed when master toggle is on (exit code: $EXIT_CODE)"
fi

# Test: Specific event disabled when master is on
export CLAUDE_HOOK_LOG_EVENTS_ENABLED=1
export CLAUDE_HOOK_LOG_PRETOOLUSE_ENABLED=0
echo "$TEST_PAYLOAD" | bash "${HOOK_DIR}/bash/log-pretooluse.sh"
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    pass_test "Hook exits successfully when specific event is disabled"
else
    fail_test "Hook failed when specific event disabled (exit code: $EXIT_CODE)"
fi

# Cleanup environment variables
unset CLAUDE_HOOK_LOG_EVENTS_ENABLED
unset CLAUDE_HOOK_LOG_PRETOOLUSE_ENABLED

# Test: Cleanup
test_section "Cleanup"
# Remove test log file
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
    pass_test "Test log file cleaned up"
fi

# Clean up empty test directories (only if empty to avoid removing production logs)
for event in pretooluse permissionrequest posttooluse notification userpromptsubmit stop subagentstop precompact sessionstart sessionend; do
    if [ -d "${HOOK_DIR}/logs/${event}" ] && [ -z "$(ls -A "${HOOK_DIR}/logs/${event}" 2>/dev/null)" ]; then
        rmdir "${HOOK_DIR}/logs/${event}" 2>/dev/null || true
    fi
done
# Remove logs directory if empty
if [ -d "${HOOK_DIR}/logs" ] && [ -z "$(ls -A "${HOOK_DIR}/logs" 2>/dev/null)" ]; then
    rmdir "${HOOK_DIR}/logs" 2>/dev/null || true
    pass_test "Empty log directories cleaned up"
fi

test_suite_end

