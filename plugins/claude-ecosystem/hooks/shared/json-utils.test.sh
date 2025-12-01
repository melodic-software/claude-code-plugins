#!/usr/bin/env bash
# json-utils.test.sh - Unit tests for JSON utility functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"
source "${SCRIPT_DIR}/json-utils.sh"

test_suite_start "JSON Utilities"

# Check if jq is available before running tests
if ! command -v jq &> /dev/null; then
    skip_test "jq not installed - skipping all JSON utility tests"
    test_suite_end
    exit 0
fi

# Test parse_json_field with valid JSON
test_section "parse_json_field Tests"

result=$(echo '{"tool_name": "Write", "tool_input": {"file_path": "/test.txt"}}' | parse_json_field "tool_name")
assert_equals "Write" "$result" "parse_json_field extracts tool name"

result=$(echo '{"tool_name": "Write", "tool_input": {"file_path": "/test.txt"}}' | parse_json_field "tool_input.file_path")
assert_equals "/test.txt" "$result" "parse_json_field extracts nested file_path"

result=$(echo '{"nested": {"value": "test"}}' | parse_json_field "nested.value")
assert_equals "test" "$result" "parse_json_field handles nested fields"

result=$(echo '{}' | parse_json_field "missing")
assert_equals "" "$result" "parse_json_field returns empty for missing field"

# Test get_tool_name
test_section "get_tool_name Tests"

result=$(echo '{"tool_name": "Bash"}' | get_tool_name)
assert_equals "Bash" "$result" "get_tool_name extracts Bash tool"

result=$(echo '{"tool_name": "Edit"}' | get_tool_name)
assert_equals "Edit" "$result" "get_tool_name extracts Edit tool"

# Test get_file_path
test_section "get_file_path Tests"

result=$(echo '{"tool_input": {"file_path": "README.md"}}' | get_file_path)
assert_equals "README.md" "$result" "get_file_path extracts file path"

result=$(echo '{"tool_name": "Write"}' | get_file_path)
assert_equals "" "$result" "get_file_path returns empty when missing"

# Test get_command
test_section "get_command Tests"

result=$(echo '{"tool_input": {"command": "git status"}}' | get_command)
assert_equals "git status" "$result" "get_command extracts command"

# Test get_content and get_new_string helpers
test_section "get_content/get_new_string Tests"

result=$(echo '{"tool_input": {"content": "new file content"}}' | get_content)
assert_equals "new file content" "$result" "get_content extracts Write payload"

result=$(echo '{"tool_input": {"new_string": "updated text"}}' | get_new_string)
assert_equals "updated text" "$result" "get_new_string extracts Edit payload"

# Test output_json_decision (uses official hookSpecificOutput schema)
test_section "output_json_decision Tests"

result=$(output_json_decision "allow")
assert_contains "$result" '"permissionDecision"' "output_json_decision includes permissionDecision field"
assert_contains "$result" '"allow"' "output_json_decision includes allow value"
assert_contains "$result" '"hookSpecificOutput"' "output_json_decision uses hookSpecificOutput wrapper"

result=$(output_json_decision "ask" "Please confirm")
assert_contains "$result" '"ask"' "output_json_decision with message includes decision"
assert_contains "$result" '"Please confirm"' "output_json_decision includes reason message"
assert_contains "$result" '"permissionDecisionReason"' "output_json_decision includes reason field"

# Test output_json_error
test_section "output_json_error Tests"

result=$(output_json_error "Test error")
assert_contains "$result" '"error"' "output_json_error includes error field"
assert_contains "$result" '"Test error"' "output_json_error includes error message"

result=$(output_json_error "Error" "Try this")
assert_contains "$result" '"suggestion"' "output_json_error with suggestion includes field"
assert_contains "$result" '"Try this"' "output_json_error includes suggestion"

# Test check_jq_available
test_section "check_jq_available Tests"

if check_jq_available; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: check_jq_available detects jq"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: check_jq_available should detect jq"
fi

test_suite_end

