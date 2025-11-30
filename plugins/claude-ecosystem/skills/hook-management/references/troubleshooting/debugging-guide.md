# Debugging Guide

**Last Updated:** 2025-11-18

## Overview

Advanced debugging techniques for troubleshooting complex hook issues.

## Table of Contents

- [Manual Testing Techniques](#manual-testing-techniques)
- [Verbose Execution](#verbose-execution)
- [Logging and Tracing](#logging-and-tracing)
- [Inspecting Variables](#inspecting-variables)
- [Breakpoint Simulation](#breakpoint-simulation)
- [Testing Configuration Changes](#testing-configuration-changes)
- [Debugging JSON Parsing](#debugging-json-parsing)
- [Debugging Shared Utilities](#debugging-shared-utilities)
- [Debugging Test Failures](#debugging-test-failures)
- [Performance Profiling](#performance-profiling)
- [Common Debug Patterns](#common-debug-patterns)
- [Troubleshooting Checklist](#troubleshooting-checklist)
- [Advanced Techniques](#advanced-techniques)
- [Reference](#reference)

## Manual Testing Techniques

### Test with Sample Payload

**Basic test:**

```bash
echo '{"tool": "Write", "file_path": "test.md"}' | \
  bash .claude/hooks/<hook-name>/bash/<hook-name>.sh

echo "Exit code: $?"
```

**Test with jq for pretty formatting:**

```bash
jq -n '{tool: "Write", file_path: "test.md", new_string: "content"}' | \
  bash .claude/hooks/<hook-name>/bash/<hook-name>.sh
```

**Capture output:**

```bash
OUTPUT=$(echo '{"tool": "Write", "file_path": "test.md"}' | \
  bash .claude/hooks/<hook-name>/bash/<hook-name>.sh 2>&1)

echo "Output: $OUTPUT"
echo "Exit code: $?"
```

### Test Multiple Scenarios

```bash
#!/usr/bin/env bash
# test-scenarios.sh

HOOK=".claude/hooks/my-hook/bash/my-hook.sh"

echo "=== Scenario 1: Valid input ==="
echo '{"tool": "Write", "file_path": "valid.txt"}' | bash $HOOK
echo "Exit code: $?"
echo

echo "=== Scenario 2: Invalid input ==="
echo '{"tool": "Write", "file_path": "invalid.bak"}' | bash $HOOK
echo "Exit code: $?"
echo

echo "=== Scenario 3: Missing field ==="
echo '{"tool": "Write"}' | bash $HOOK
echo "Exit code: $?"
```

Make executable and run:

```bash
chmod +x test-scenarios.sh
./test-scenarios.sh
```

## Verbose Execution

### Enable Bash Debugging

Add to top of hook script (temporarily):

```bash
#!/usr/bin/env bash
set -x  # Print commands as they execute
set -euo pipefail
```

**Output shows:**

```text
+ SCRIPT_DIR=/path/to/hooks/my-hook/bash
+ source /path/to/hooks/shared/json-utils.sh
+ INPUT='{"tool": "Write", "file_path": "test.md"}'
+ TOOL=Write
+ FILE_PATH=test.md
```

### Selective Debugging

Debug only specific sections:

```bash
# Enable debugging for section
set -x
RESULT=$(complex_operation)
set +x  # Disable debugging

# Rest of script runs normally
```

## Logging and Tracing

### Add Debug Output

```bash
echo "DEBUG: Entered validation function" >&2
echo "DEBUG: TOOL=$TOOL" >&2
echo "DEBUG: FILE_PATH=$FILE_PATH" >&2
```

### Use log_message Helper

```bash
source "${SCRIPT_DIR}/../../shared/config-utils.sh"

log_message "debug" "Processing file: $FILE_PATH"
log_message "debug" "Current enforcement: $ENFORCEMENT"
log_message "debug" "Pattern match result: $MATCH"
```

Control verbosity via config:

```yaml
# .claude/hooks/config/global.yaml
log_level: debug  # Show all debug logs
```

### Trace Function Calls

```bash
# Add at function entry
function my_function() {
    echo "TRACE: Entered my_function($*)" >&2

    # Function logic

    echo "TRACE: Exiting my_function" >&2
}
```

## Inspecting Variables

### Print All Variables

```bash
echo "=== All Variables ===" >&2
set | grep -E '^(TOOL|FILE_PATH|CONFIG|ENFORCEMENT)=' >&2
```

### Pretty Print JSON

```bash
echo "=== Input Payload ===" >&2
echo "$INPUT" | jq '.' >&2
```

### Print Array Contents

```bash
echo "=== Excluded Paths ===" >&2
for path in "${EXCLUDED_PATHS[@]}"; do
    echo "  - $path" >&2
done
```

## Breakpoint Simulation

### Pause for Inspection

```bash
# Pause execution for inspection
echo "BREAKPOINT: About to validate file" >&2
read -p "Press Enter to continue..."
```

### Conditional Breakpoints

```bash
if [[ "$FILE_PATH" == "specific-file.md" ]]; then
    echo "BREAKPOINT: Matched specific file" >&2
    echo "TOOL=$TOOL" >&2
    echo "FILE_PATH=$FILE_PATH" >&2
    read -p "Press Enter to continue..."
fi
```

## Testing Configuration Changes

### Test with Modified Config

```bash
#!/usr/bin/env bash
# test-with-config.sh

HOOK_DIR=".claude/hooks/my-hook"
CONFIG="${HOOK_DIR}/hook.yaml"
BACKUP="${HOOK_DIR}/hook.yaml.backup"

# Backup original
cp "$CONFIG" "$BACKUP"

# Modify for testing
cat > "$CONFIG" <<'EOF'
enabled: false
enforcement: warn
EOF

# Test
echo '{"tool": "Write", "file_path": "test.md"}' | \
  bash "${HOOK_DIR}/bash/my-hook.sh"

# Restore
mv "$BACKUP" "$CONFIG"
```

### Test Different Enforcement Modes

```bash
for mode in block warn log; do
    echo "=== Testing enforcement: $mode ===" >&2

    # Modify config
    sed -i "s/enforcement:.*/enforcement: $mode/" hook.yaml

    # Test
    echo '{"tool": "Write", "file_path": "invalid.bak"}' | \
      bash hook-script.sh

    echo "Exit code: $?"
    echo
done
```

## Debugging JSON Parsing

### Validate JSON Input

```bash
if ! echo "$INPUT" | jq '.' >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON input" >&2
    echo "Input was: $INPUT" >&2
    exit 3
fi
```

### Inspect Parsed Fields

```bash
echo "=== Parsed Fields ===" >&2
echo "tool: $(echo "$INPUT" | jq -r '.tool // "MISSING"')" >&2
echo "file_path: $(echo "$INPUT" | jq -r '.file_path // "MISSING"')" >&2
echo "command: $(echo "$INPUT" | jq -r '.command // "MISSING"')" >&2
```

### Test jq Queries

```bash
# Test query interactively
echo '{"tool": "Write", "file_path": "test.md"}' | jq '.tool'
echo '{"tool": "Write", "file_path": "test.md"}' | jq '.file_path'
echo '{"tool": "Write", "file_path": "test.md"}' | jq -r '.tool // "default"'
```

## Debugging Shared Utilities

### Test Utility Functions

```bash
#!/usr/bin/env bash
# test-utils.sh

source .claude/hooks/shared/json-utils.sh

INPUT='{"tool": "Write", "file_path": "test.md"}'

echo "Testing get_tool_name..."
TOOL=$(echo "$INPUT" | get_tool_name)
echo "Result: $TOOL"

echo "Testing get_file_path..."
FILE_PATH=$(echo "$INPUT" | get_file_path)
echo "Result: $FILE_PATH"
```

### Unit Test Utilities

```bash
bash .claude/hooks/shared/json-utils.test.sh
bash .claude/hooks/shared/path-utils.test.sh
bash .claude/hooks/shared/config-utils.test.sh
```

## Debugging Test Failures

### Run Tests with Verbose Output

```bash
# Enable bash debugging in test script
export DEBUG=1
bash .claude/hooks/my-hook/tests/integration.test.sh
```

### Run Single Test Section

Comment out other sections:

```bash
# test_section "Section 1"
# ...

test_section "Section 2 (debugging this)"
# Only this section runs
```

### Print Test Values

```bash
test_section "Debug Section"

PAYLOAD='{"tool": "Write", "file_path": "test.md"}'
echo "DEBUG: PAYLOAD=$PAYLOAD" >&2

RESULT=$(echo "$PAYLOAD" | bash hook-script.sh 2>&1)
echo "DEBUG: RESULT=$RESULT" >&2

EXIT_CODE=$?
echo "DEBUG: EXIT_CODE=$EXIT_CODE" >&2

assert_exit_code 0 $EXIT_CODE "Should pass"
```

## Performance Profiling

### Time Hook Execution

```bash
time echo '{"tool": "Write", "file_path": "test.md"}' | \
  bash .claude/hooks/my-hook/bash/my-hook.sh
```

**Output:**

```text
real    0m0.145s
user    0m0.098s
sys     0m0.047s
```

### Profile Specific Operations

```bash
START=$(date +%s%N)

# Operation to profile
RESULT=$(expensive_operation)

END=$(date +%s%N)
DURATION=$(( (END - START) / 1000000 ))

echo "Operation took: ${DURATION}ms" >&2
```

### Identify Bottlenecks

```bash
#!/usr/bin/env bash
set -x  # Verbose output

# Time each operation
time source shared/json-utils.sh
time source shared/config-utils.sh
time is_hook_enabled "$CONFIG"
time validation_logic
```

## Common Debug Patterns

### Pattern 1: Unexpected Exit Code

```bash
echo '{"tool": "Write", "file_path": "test.md"}' | \
  bash hook-script.sh

EXIT_CODE=$?
case $EXIT_CODE in
    0) echo "Success (allow)" ;;
    1) echo "Warning (non-blocking)" ;;
    2) echo "Block" ;;
    3) echo "Error (dependency/config)" ;;
    *) echo "Unexpected exit code: $EXIT_CODE" ;;
esac
```

### Pattern 2: Silent Failure

```bash
set -euo pipefail  # Fail fast

# Wrap operations in explicit error handling
if ! operation; then
    echo "ERROR: operation failed" >&2
    exit 3
fi
```

### Pattern 3: Regex Not Matching

```bash
PATTERN='\.bak$'
INPUT='test.bak'

if [[ "$INPUT" =~ $PATTERN ]]; then
    echo "Match: $INPUT matches $PATTERN"
else
    echo "No match: $INPUT doesn't match $PATTERN"
    echo "Check pattern syntax"
fi
```

## Troubleshooting Checklist

When debugging hook issues:

- [ ] Test hook directly with sample payload
- [ ] Enable verbose logging (set -x)
- [ ] Check all exit codes
- [ ] Verify JSON parsing
- [ ] Inspect intermediate variables
- [ ] Test with minimal input
- [ ] Test with real-world input
- [ ] Check dependencies (jq, yq, git)
- [ ] Verify config is loaded correctly
- [ ] Run integration tests
- [ ] Check for race conditions
- [ ] Profile performance
- [ ] Review shared utilities
- [ ] Test on different platforms (if applicable)

## Advanced Techniques

### Attach Debugger (bash)

```bash
# Install bashdb
# On macOS: brew install bashdb
# On Linux: apt-get install bashdb

# Debug hook
bashdb .claude/hooks/my-hook/bash/my-hook.sh <<< '{"tool": "Write"}'

# Use commands:
# s - step
# n - next
# c - continue
# p $VAR - print variable
# l - list code
# q - quit
```

### Compare Expected vs Actual

```bash
EXPECTED="expected output"
ACTUAL=$(echo '{"tool": "Write"}' | bash hook-script.sh 2>&1)

if [[ "$EXPECTED" == "$ACTUAL" ]]; then
    echo "✅ Match"
else
    echo "❌ Mismatch"
    echo "Expected: $EXPECTED"
    echo "Actual:   $ACTUAL"
fi
```

### Capture Full Execution Trace

```bash
bash -x .claude/hooks/my-hook/bash/my-hook.sh 2>&1 | tee debug.log <<< '{"tool": "Write"}'
```

Review `debug.log` for full execution trace.

## Reference

- **Common Issues:** [common-issues.md](common-issues.md)
- **Testing Guide:** [../development/testing-guide.md](../development/testing-guide.md)
- **Best Practices:** [../development/best-practices.md](../development/best-practices.md)
