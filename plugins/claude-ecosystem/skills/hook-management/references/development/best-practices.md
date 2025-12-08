# Hook Development Best Practices

**Last Updated:** 2025-11-25

## Overview

Collection of best practices, patterns, and recommendations for developing high-quality hooks.

## Table of Contents

- [Script Requirements](#script-requirements)
- [Error Handling](#error-handling)
- [Performance Optimization](#performance-optimization)
- [Cross-Platform Compatibility](#cross-platform-compatibility)
- [Configuration Best Practices](#configuration-best-practices)
- [Testing Best Practices](#testing-best-practices)
- [Code Organization](#code-organization)
- [Documentation Best Practices](#documentation-best-practices)
- [Security Considerations](#security-considerations)
- [Maintenance Best Practices](#maintenance-best-practices)
- [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
- [Reference](#reference)

## Script Requirements

### 1. Accept JSON via stdin

All hook payloads come from Claude Code via standard input:

```bash
INPUT=$(cat)
```

Never prompt for user input or read from files - hooks are non-interactive.

### 2. Parse with jq

Use `json-utils.sh` helpers for consistent JSON parsing:

```bash
source "${SCRIPT_DIR}/../../shared/json-utils.sh"

TOOL=$(echo "$INPUT" | get_tool_name)
FILE_PATH=$(echo "$INPUT" | get_file_path)
COMMAND=$(echo "$INPUT" | get_command)
```

### 3. Load Config on Each Run

Enable hot reload by loading config on each execution:

```bash
CONFIG="${SCRIPT_DIR}/../config.yaml"
is_hook_enabled "$CONFIG" || exit 0
```

Do NOT cache config in memory between hook executions.

### 4. Check Enabled State Early

First operation should be checking if hook is enabled:

```bash
# Check if hook is enabled (global + per-hook)
is_hook_enabled "$CONFIG" || exit 0
```

This allows quick bypass when hook is disabled.

### 5. Exit with Correct Codes

**Standard exit codes:**

- `0` - Success (allow operation)
- `1` - Warning (non-blocking)
- `2` - Block operation
- `3` - Error (missing dependencies, config errors)

**Example:**

```bash
# Success
exit 0

# Warning
echo "WARN: Potential issue detected" >&2
exit 1

# Block
echo "ERROR: Operation not allowed" >&2
exit 2

# Error
echo "ERROR: Missing dependency: jq" >&2
exit 3
```

### 6. Include systemMessage for User Feedback

All hooks should output a descriptive `systemMessage` in their JSON output so users can see what hooks are being fired:

```bash
# Format: {hook-name}: {brief-action}
# Keep messages under 50 characters

# For success/allow cases with JSON output:
cat << EOF
{
  "systemMessage": "my-hook: action completed",
  "hookSpecificOutput": { ... }
}
EOF

# For simple success cases:
echo '{"systemMessage":"my-hook: pattern validated"}'
exit 0
```

**Message Guidelines:**

| Scenario | Message Pattern | Example |
|----------|-----------------|---------|
| Context injection | `{hook}: {noun} {past-verb}` | `inject-best-practices: reminder loaded` |
| Validation pass | `{hook}: pattern validated` | `prevent-backup-files: pattern validated` |
| Detection | `{hook}: [{topic}] detected` | `docs-management: [hooks] detected` |
| Disabled | `{hook}: disabled` | `markdown-lint: disabled` |
| Skipped | `{hook}: skipped ({reason})` | `markdown-lint: skipped (not markdown)` |
| Active state | `{hook}: {noun} active` | `source-citation: requirements active` |

**When to omit systemMessage:**

- Logging/observability hooks (would create noise on every event)
- Blocking hooks (exit code 2) use stderr for error messages instead

### 7. Log Appropriately

Use `log_message()` with appropriate levels:

```bash
log_message "debug" "Processing file: ${FILE_PATH}"
log_message "info" "Hook validation passed"
log_message "warn" "Potential issue: ${DETAILS}"
log_message "error" "Critical failure: ${ERROR}"
```

Logs respect global log_level configuration.

### 8. Handle Missing Dependencies

Check for required tools and provide helpful error messages:

```bash
check_jq_available || exit 3

if ! command -v git &>/dev/null; then
    echo "ERROR: git required but not found" >&2
    exit 3
fi
```

### 9. Source from Script Location

Use `$SCRIPT_DIR` for portability:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../shared/json-utils.sh"
source "${SCRIPT_DIR}/../../shared/config-utils.sh"
```

Never use relative paths from current working directory.

## Error Handling

### Fail Fast with set -euo pipefail

```bash
#!/usr/bin/env bash
set -euo pipefail
```

**What this does:**

- `set -e` - Exit on any error
- `set -u` - Error on undefined variables
- `set -o pipefail` - Exit if any command in pipeline fails

### Validate Input Fields

```bash
TOOL=$(echo "$INPUT" | get_tool_name)

if [[ -z "$TOOL" ]]; then
    echo "ERROR: Missing 'tool' field in payload" >&2
    exit 3
fi
```

### Handle Optional Fields Gracefully

```bash
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // ""')

# Only process if file_path exists
if [[ -n "$FILE_PATH" ]]; then
    # Validation logic
fi
```

### Provide Actionable Error Messages

```bash
# ❌ Bad
echo "ERROR: Invalid" >&2

# ✅ Good
echo "ERROR: File extension '.bak' not allowed for git-tracked files" >&2
echo "SUGGESTION: Use version control instead of backup files" >&2
echo "See CLAUDE.md for rationale" >&2
```

## Performance Optimization

### Exit Early

```bash
# Check enabled first (fast bypass)
is_hook_enabled "$CONFIG" || exit 0

# Check tool matcher early
TOOL=$(echo "$INPUT" | get_tool_name)
[[ "$TOOL" =~ ^(Write|Edit)$ ]] || exit 0

# Only then do expensive operations
```

### Cache Expensive Operations

```bash
# Load config once
CONFIG="${SCRIPT_DIR}/../config.yaml"
ENFORCEMENT=$(load_enforcement_mode "$CONFIG")

# Reuse loaded value
if [[ "$ENFORCEMENT" == "block" ]]; then
    exit 2
elif [[ "$ENFORCEMENT" == "warn" ]]; then
    exit 1
fi
```

### Use Efficient Text Processing

```bash
# ✅ Fast: Use grep
if echo "$CONTENT" | grep -q 'pattern'; then
    # ...
fi

# ❌ Slow: Use awk/sed for simple matches
if echo "$CONTENT" | awk '/pattern/ {found=1} END {exit !found}'; then
    # ...
fi
```

## Cross-Platform Compatibility

### Use Portable Bash

Target bash 4.0+ for cross-platform compatibility:

```bash
# ✅ Portable
if [[ "$VAR" =~ pattern ]]; then

# ❌ Bash 4.3+ only
declare -A assoc_array
```

### Handle Path Separators

```bash
# ✅ Portable
SHARED_DIR="${SCRIPT_DIR}/../../shared"

# ❌ Platform-specific
SHARED_DIR="${SCRIPT_DIR}\..\..\shared"  # Windows only
```

### Test on Multiple Platforms

If possible, test hooks on:

- Windows (via Git Bash)
- macOS
- Linux

Use CI/CD to automate cross-platform testing.

## Configuration Best Practices

### Use Meaningful Defaults

```yaml
enforcement: block  # Safe default
timeout_seconds: 10  # Reasonable default
enabled: true  # Active by default
```

### Document Configuration Options

```yaml
# Enforcement mode determines exit code:
# - block: exit 2 (prevents operation)
# - warn: exit 1 (allows with warning)
# - log: exit 0 (silent logging)
enforcement: block
```

### Version Configuration Schema

```yaml
name: hook-name
version: 1.2.0  # Semantic versioning
```

Increment version on breaking config changes.

## Testing Best Practices

### Test All Exit Codes

```bash
test_section "Success Case"
assert_exit_code 0 "valid input"

test_section "Warning Case"
assert_exit_code 1 "warning input"

test_section "Block Case"
assert_exit_code 2 "invalid input"

test_section "Error Case"
assert_exit_code 3 "missing dependency"
```

### Test Configuration Changes

```bash
test_section "Hook Disabled"
# Temporarily disable
echo "enabled: false" > config.yaml
assert_exit_code 0 "any input when disabled"

# Restore
restore_config
```

### Use Fixtures for Consistency

```bash
# Store sample payloads
VALID_PAYLOAD=$(cat tests/fixtures/valid.json)
INVALID_PAYLOAD=$(cat tests/fixtures/invalid.json)

# Reuse in tests
echo "$VALID_PAYLOAD" | bash hook-script.sh
```

For complete testing guide, see [testing-guide.md](testing-guide.md).

## Code Organization

### Keep Hooks Focused

Each hook should have single, clear responsibility:

```text
✅ Good: prevent-backup-files (one purpose)
❌ Bad: validate-all-files (too broad)
```

### Use Shared Utilities

Extract common logic to shared utilities:

```bash
# Instead of duplicating in each hook:
TOOL=$(echo "$INPUT" | jq -r '.tool // ""')

# Use shared helper:
source "${SCRIPT_DIR}/../../shared/json-utils.sh"
TOOL=$(echo "$INPUT" | get_tool_name)
```

### Follow Vertical Slice Architecture

Keep everything for one hook in one directory:

```text
my-hook/
├── bash/hook-script.sh    # Implementation
├── config.yaml            # User configuration
├── hook.yaml              # Hook metadata
├── README.md              # Documentation
└── tests/                 # Tests
```

## Documentation Best Practices

### Document Hook Purpose Clearly

```markdown
## Purpose

Block creation of .bak, .backup, and similar files for git-tracked content.

**Rationale:** Version control provides better backup/history than file copies.
```

### Include Examples

```markdown
## Examples

### Blocked Operation

Input: `Write` tool with file_path="docs/guide.md.bak"
Output: Exit 2, "Backup files not allowed for tracked content"

### Allowed Operation

Input: `Write` tool with file_path="docs/guide.md"
Output: Exit 0
```

### Document Configuration

```markdown
## Configuration

- enabled: true/false (enable/disable hook)
- enforcement: block/warn/log (enforcement mode)
- patterns.excluded_paths: Array of paths to exclude
```

## Security Considerations

### Never Execute User-Provided Code

```bash
# ❌ Dangerous
eval "$USER_INPUT"

# ✅ Safe
# Validate and sanitize input
```

### Validate File Paths

```bash
# Prevent path traversal
if [[ "$FILE_PATH" == *".."* ]]; then
    echo "ERROR: Path traversal not allowed" >&2
    exit 2
fi
```

### Limit Resource Usage

```bash
# Set timeout in config.yaml
timeout_seconds: 10

# Don't process unbounded input
head -n 1000 < input.txt
```

## Maintenance Best Practices

### Version Your Hooks

```yaml
name: hook-name
version: 1.0.0

# Increment on changes:
# 1.0.0 → 1.0.1 (bug fix)
# 1.0.0 → 1.1.0 (new feature, backward compatible)
# 1.0.0 → 2.0.0 (breaking change)
```

### Keep Change Log

```markdown
## Version History

- v1.1.0 (2025-11-18): Added support for Python implementation
- v1.0.1 (2025-11-15): Fixed false positive for certain file patterns
- v1.0.0 (2025-11-10): Initial release
```

### Monitor for False Positives

After deploying hook:

1. Monitor for blocked operations
2. Collect feedback from team
3. Adjust patterns to reduce false positives
4. Consider enforcement=warn during initial rollout

## Anti-Patterns to Avoid

### ❌ Hardcoded Paths

```bash
# Bad
CONFIG="/absolute/path/to/config.yaml"

# Good
CONFIG="${SCRIPT_DIR}/../config.yaml"
```

### ❌ Silent Failures

```bash
# Bad
some_command || true  # Ignores errors

# Good
if ! some_command; then
    echo "ERROR: Command failed" >&2
    exit 3
fi
```

### ❌ Complex Logic in Hook Scripts

```bash
# Bad: 500 lines of complex parsing

# Good: Extract to shared utilities or use Python/TypeScript
```

### ❌ Ignoring Config

```bash
# Bad
exit 2  # Always blocks, ignores enforcement mode

# Good
ENFORCEMENT=$(load_enforcement_mode "$CONFIG")
if [[ "$ENFORCEMENT" == "warn" ]]; then
    exit 1
else
    exit 2
fi
```

### ❌ Long Running Operations

```bash
# Bad
curl https://slow-api.example.com  # May timeout

# Good
# Set reasonable timeout in config.yaml
timeout_seconds: 5
```

## Reference

- **Creating Hooks:** [creating-hooks-workflow.md](creating-hooks-workflow.md)
- **Testing Guide:** [testing-guide.md](testing-guide.md)
- **Configuration:** [../configuration/hook-config-guide.md](../configuration/hook-config-guide.md)
- **Shared Utilities:** `.claude/hooks/shared/`
