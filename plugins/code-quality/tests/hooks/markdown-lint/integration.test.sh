#!/usr/bin/env bash
# integration.test.sh - Integration tests for markdown-lint hook

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PLUGIN_ROOT}/scripts/shared/test-helpers.sh"

test_suite_start "markdown-lint Integration Tests"

# Test: Hook script exists and is executable
test_section "Hook Setup"
assert_file_exists "${PLUGIN_ROOT}/scripts/hooks/markdown-lint.sh" "Hook script exists"
assert_file_exists "${PLUGIN_ROOT}/hooks/hooks.json" "Hook configuration exists"

# Test: Hook allows non-markdown files
test_section "File Type Filtering"
PAYLOAD='{"tool_name": "Write", "tool_input": {"file_path": "test.txt", "content": "content"}}'
EXIT_CODE=0
echo "$PAYLOAD" | "${PLUGIN_ROOT}/scripts/hooks/markdown-lint.sh" &> /dev/null && EXIT_CODE=$? || EXIT_CODE=$?
assert_equals "$EXIT_CODE" "0" "Non-markdown file allowed (exit 0)"

# Test: Hook allows excluded paths
test_section "Path Exclusion"
PAYLOAD='{"tool_name": "Write", "tool_input": {"file_path": ".claude/temp/test.md", "content": "# Test"}}'
EXIT_CODE=0
echo "$PAYLOAD" | "${PLUGIN_ROOT}/scripts/hooks/markdown-lint.sh" &> /dev/null && EXIT_CODE=$? || EXIT_CODE=$?
assert_equals "$EXIT_CODE" "0" "Excluded path allowed (exit 0)"

# Note: Actual linting tests would require:
# 1. Creating temporary markdown files with known violations
# 2. Running markdownlint-cli2 on them
# 3. Verifying auto-fix behavior
# 4. Checking for unfixable errors
# These are complex integration tests that require markdownlint-cli2 to be installed
# and would create/modify files in the repository

test_section "Hook Behavior (Comprehensive Tests)"
skip_test "Comprehensive integration tests require markdownlint-cli2 and file manipulation"

test_suite_end
