# Testing Guide

**Last Updated:** 2025-11-18

## Overview

Comprehensive guide to testing hooks using the vertical slice testing pattern with co-located tests.

## Testing Philosophy

**Tests are co-located with the code they test:**

- Unit tests next to shared utilities (`*.test.sh` next to `*.sh`)
- Integration tests in hook's `tests/` directory
- High cohesion: Tests live with the code
- Low coupling: Each hook's tests are independent
- Vertical slice: Delete hook = delete tests automatically

## Test Directory Structure

```text
.claude/hooks/
├── shared/
│   ├── json-utils.sh
│   ├── json-utils.test.sh      # Unit test next to implementation
│   └── test-helpers.sh         # Shared test utilities
├── prevent-backup-files/
│   ├── bash/prevent-backup-files.sh
│   ├── hook.yaml
│   └── tests/
│       ├── integration.test.sh  # Tests for THIS hook only
│       └── fixtures/            # Test data for this hook
└── test-runner.sh               # Discovers all *.test.sh
```

## Test Framework (test-helpers.sh)

### Available Assertions

**Value equality:**

```bash
assert_equals "expected" "actual" "Description of test"
```

**Exit code validation:**

```bash
assert_exit_code 0 "command" "Description"
assert_exit_code 2 "command" "Should block"
```

**Substring matching:**

```bash
assert_contains "substring" "full string" "Description"
```

**File existence:**

```bash
assert_file_exists "/path/to/file" "Description"
```

**Command execution:**

```bash
run_command "bash script.sh"
assert_exit_code 0 "$?" "Script should succeed"
```

### Test Suite Structure

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../shared/test-helpers.sh"

test_suite_start "My Test Suite Name"

test_section "Section 1: Setup Tests"
assert_file_exists "file.sh" "Script exists"
assert_equals "expected" "actual" "Values match"

test_section "Section 2: Behavior Tests"
run_command "bash script.sh input"
assert_exit_code 0 "$?" "Command succeeds"

test_suite_end
```

### Skip Tests Conditionally

```bash
if [[ ! -command -v jq ]]; then
    skip_test "jq not installed"
fi
```

## Running Tests

### All Tests

```bash
bash .claude/hooks/test-runner.sh
```

**Output:**

```text
Running tests in .claude/hooks...

=== json-utils.test.sh ===
✅ All tests passed (5/5)

=== prevent-backup-files/tests/integration.test.sh ===
✅ All tests passed (8/8)

Total: 13 tests passed
```

### Specific Hook Tests

```bash
bash .claude/hooks/prevent-backup-files/tests/integration.test.sh
```

### Specific Utility Tests

```bash
bash .claude/hooks/shared/json-utils.test.sh
```

## Writing Integration Tests

### Test Template

```bash
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${HOOK_DIR}/../shared/test-helpers.sh"

test_suite_start "hook-name Integration Tests"

test_section "Hook Setup"
assert_file_exists "${HOOK_DIR}/bash/hook-name.sh" "Hook script exists"
assert_file_exists "${HOOK_DIR}/hook.yaml" "Hook config exists"

test_section "Hook Behavior - Allow Operation"
PAYLOAD='{"tool": "Write", "file_path": "valid-file.txt"}'
RESULT=$(echo "$PAYLOAD" | bash "${HOOK_DIR}/bash/hook-name.sh" 2>&1)
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Should allow valid operation"

test_section "Hook Behavior - Block Operation"
PAYLOAD='{"tool": "Write", "file_path": "invalid-file.bak"}'
RESULT=$(echo "$PAYLOAD" | bash "${HOOK_DIR}/bash/hook-name.sh" 2>&1)
EXIT_CODE=$?
assert_exit_code 2 $EXIT_CODE "Should block invalid operation"
assert_contains "ERROR" "$RESULT" "Should output error message"

test_section "Hook Disabled"
# Temporarily disable hook
TEMP_CONFIG="${HOOK_DIR}/hook.yaml.backup"
cp "${HOOK_DIR}/hook.yaml" "$TEMP_CONFIG"
echo "enabled: false" > "${HOOK_DIR}/hook.yaml"

PAYLOAD='{"tool": "Write", "file_path": "any-file.txt"}'
RESULT=$(echo "$PAYLOAD" | bash "${HOOK_DIR}/bash/hook-name.sh" 2>&1)
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Should bypass when disabled"

# Restore config
mv "$TEMP_CONFIG" "${HOOK_DIR}/hook.yaml"

test_suite_end
```

### Test Scenarios to Cover

1. **Setup validation:**
   - Hook script exists
   - Config file exists
   - Dependencies available

2. **Basic behavior:**
   - Valid input → Exit 0
   - Invalid input → Exit 2 (block)
   - Warning input → Exit 1 (warn)

3. **Configuration:**
   - Hook disabled → Bypass validation
   - Enforcement=warn → Exit 1 instead of 2
   - Enforcement=log → Exit 0 with stderr

4. **Edge cases:**
   - Missing file_path
   - Invalid JSON input
   - Empty strings
   - Unusual file extensions

5. **Error handling:**
   - Missing dependencies → Exit 3
   - Invalid config → Exit 3
   - Timeout conditions

## Test Fixtures

Store sample data in `tests/fixtures/`:

```text
tests/
├── integration.test.sh
└── fixtures/
    ├── payloads.json           # Sample JSON inputs
    ├── valid-input.txt         # Valid test data
    └── invalid-input.txt       # Invalid test data
```

**Example fixtures/payloads.json:**

```json
{
  "valid_write": {
    "tool": "Write",
    "file_path": "docs/guide.md",
    "content": "Valid content"
  },
  "backup_file": {
    "tool": "Write",
    "file_path": "docs/guide.md.bak",
    "content": "Backup content"
  }
}
```

**Using fixtures:**

```bash
VALID_PAYLOAD=$(jq '.valid_write' < "${SCRIPT_DIR}/fixtures/payloads.json")
echo "$VALID_PAYLOAD" | bash "${HOOK_DIR}/bash/hook-name.sh"
```

## Manual Testing

### Test Hook Directly

```bash
echo '{"tool": "Write", "file_path": "test.bak"}' | \
  bash .claude/hooks/prevent-backup-files/bash/prevent-backup-files.sh

echo "Exit code: $?"
```

### Test with jq Pretty Print

```bash
jq -n '{tool: "Write", file_path: "test.md"}' | \
  bash .claude/hooks/block-absolute-paths/bash/block-absolute-paths.sh
```

### Test Multiple Scenarios

```bash
# Create test script
cat > test-scenarios.sh <<'EOF'
#!/usr/bin/env bash
HOOK="bash .claude/hooks/my-hook/bash/my-hook.sh"

# Scenario 1
echo '{"tool": "Write", "file_path": "valid.txt"}' | $HOOK
echo "Scenario 1 (valid): Exit $?"

# Scenario 2
echo '{"tool": "Write", "file_path": "invalid.bak"}' | $HOOK
echo "Scenario 2 (invalid): Exit $?"
EOF

bash test-scenarios.sh
```

## Test-Driven Development Workflow

### 1. Write Failing Test First

```bash
test_section "Should block backup files"
PAYLOAD='{"tool": "Write", "file_path": "test.bak"}'
RESULT=$(echo "$PAYLOAD" | bash "${HOOK_DIR}/bash/hook-name.sh" 2>&1)
assert_exit_code 2 $? "Should block .bak files"
```

### 2. Implement Hook Logic

```bash
# In hook script
if [[ "$FILE_PATH" =~ \.bak$ ]]; then
    echo "ERROR: Backup files not allowed" >&2
    exit 2
fi
```

### 3. Run Test (Should Pass)

```bash
bash .claude/hooks/hook-name/tests/integration.test.sh
```

### 4. Refactor if Needed

### 5. Add More Tests

## Continuous Testing During Development

**Watch mode (bash):**

```bash
while true; do
    clear
    bash .claude/hooks/my-hook/tests/integration.test.sh
    sleep 2
done
```

**Run on file change (using entr):**

```bash
ls .claude/hooks/my-hook/bash/*.sh | entr -c bash .claude/hooks/my-hook/tests/integration.test.sh
```

## Debugging Test Failures

### Enable Verbose Output

```bash
set -x  # Add to test script for verbose execution
bash .claude/hooks/my-hook/tests/integration.test.sh
```

### Print Intermediate Values

```bash
RESULT=$(echo "$PAYLOAD" | bash "${HOOK_DIR}/bash/hook-name.sh" 2>&1)
echo "RESULT: $RESULT"  # Debug output
echo "EXIT_CODE: $?"
```

### Test One Section at a Time

Comment out other sections:

```bash
# test_section "Section 1"
# ...

test_section "Section 2 (debugging this)"
# Only this runs
```

## Best Practices

1. **Test all exit codes:**
   - 0 (success)
   - 1 (warn)
   - 2 (block)
   - 3 (error)

2. **Test with real payloads:**
   - Copy actual JSON from Claude Code hook execution
   - Add to fixtures for regression testing

3. **Test configuration changes:**
   - enabled=true/false
   - enforcement modes
   - pattern modifications

4. **Keep tests fast:**
   - Avoid slow operations
   - Use fixtures instead of generating data
   - Mock expensive dependencies

5. **Test edge cases:**
   - Empty strings
   - Special characters
   - Unusual file paths
   - Missing fields

6. **Document test scenarios:**
   - Add comments explaining why test exists
   - Reference related issues or bugs

## Reference

- **Test Runner:** `.claude/hooks/test-runner.sh`
- **Test Helpers:** `.claude/hooks/shared/test-helpers.sh`
- **Example Tests:** `.claude/hooks/prevent-backup-files/tests/integration.test.sh`
- **Creating Hooks:** [creating-hooks-workflow.md](creating-hooks-workflow.md)
