# Creating Hooks Workflow

**Last Updated:** 2025-11-25

## Overview

Step-by-step guide for creating new hooks from scratch, following vertical slice architecture and best practices.

## Prerequisites

Before creating a new hook:

1. **Understand hook events** - Query docs-management skill for "PreToolUse, PostToolUse, SessionEnd hook events"
2. **Know your requirements** - What should the hook validate or enforce?
3. **Choose implementation language** - Start with bash (simplest), migrate to Python/TypeScript if needed

## Step-by-Step Workflow

### Step 1: Create Hook Directory Structure

```bash
mkdir -p .claude/hooks/my-new-hook/bash
mkdir -p .claude/hooks/my-new-hook/tests/fixtures
```

**Vertical slice principle:** All hook code, config, docs, and tests in one directory.

### Step 2: Create config.yaml (User Configuration)

Create the user-facing configuration file:

```yaml
# .claude/hooks/my-new-hook/config.yaml
# User-facing configuration - changes take effect immediately

# Hook control
enabled: true

# Enforcement mode: block, warn, log
enforcement: block

# Exit codes
exit_code: 2   # Used when enforcement is 'block'
warn_code: 1   # Used when enforcement is 'warn'

# Implementation selection
implementations:
  available: [bash]
  active: bash

# Hook-specific patterns
patterns:
  excluded_paths:
    - '.git'
    - 'node_modules'

# User-facing messages
messages:
  violation: "Violation detected: {{details}}"
  suggestion: "How to fix this issue"
  documentation: "See CLAUDE.md for rationale"
```

### Step 3: Create hook.yaml (Metadata)

Create the hook metadata file:

```yaml
# .claude/hooks/my-new-hook/hook.yaml
# Reference metadata - for documentation purposes
name: my-new-hook
version: 1.0.0
description: Brief description of what this hook does

implementations:
  bash:
    entry_point: bash/my-new-hook.sh
    handler: main
    minimum_version: "4.0"
    available: true
  python:
    entry_point: python/my_new_hook.py
    available: false
  typescript:
    entry_point: typescript/dist/index.js
    available: false

selection:
  strategy: preference_order
  preference_order: [bash]
  active: bash

timeout_seconds: 10
concurrent_safe: true
```

### Step 4: Create Implementation Script

```bash
#!/usr/bin/env bash
# .claude/hooks/my-new-hook/bash/my-new-hook.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities (from bash/ subdirectory)
source "${SCRIPT_DIR}/../../shared/json-utils.sh" || { echo "ERROR: Cannot load json-utils.sh" >&2; exit 3; }
source "${SCRIPT_DIR}/../../shared/config-utils.sh" || { echo "ERROR: Cannot load config-utils.sh" >&2; exit 3; }

# Load config from config.yaml (user-facing configuration)
CONFIG="${SCRIPT_DIR}/../config.yaml"

# Check if hook is enabled
is_hook_enabled "$CONFIG" || exit 0

# Check dependencies
check_jq_available || exit 3

# Read JSON input from stdin
INPUT=$(cat)

# Your validation logic here
TOOL=$(echo "$INPUT" | get_tool_name)
# ... hook logic ...

# Exit with appropriate code
exit 0  # or 2 to block, 1 to warn
```

**Script requirements:**

1. Accept JSON via stdin
2. Parse with jq (use json-utils.sh helpers)
3. Load config on each run (enables hot reload)
4. Check enabled state with `is_hook_enabled()`
5. Exit with correct codes (0=success, 1=warn, 2=block, 3=error)
6. Log appropriately with `log_message()`
7. Handle missing dependencies gracefully
8. Source utilities from script location (use `$SCRIPT_DIR`)

### Step 5: Create Integration Tests

```bash
#!/usr/bin/env bash
# .claude/hooks/my-new-hook/tests/integration.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${HOOK_DIR}/../shared/test-helpers.sh"

test_suite_start "my-new-hook Integration Tests"

test_section "Hook Setup"
assert_file_exists "${HOOK_DIR}/bash/my-new-hook.sh" "Hook script exists"
assert_file_exists "${HOOK_DIR}/hook.yaml" "Hook config exists"

test_section "Hook Behavior"
# Add your test scenarios here

test_suite_end
```

**Test organization:**

- Integration tests in `tests/integration.test.sh`
- Test fixtures in `tests/fixtures/`
- Use `test-helpers.sh` assertion framework

For complete testing guide, see [testing-guide.md](testing-guide.md).

### Step 6: Register in .claude/settings.json

**IMPORTANT:** Matcher must be a **string** (not object):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",  // String regex pattern
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/my-new-hook/bash/my-new-hook.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Hook event types:**

- **PreToolUse** - Runs before tool execution (validation, blocking)
- **PostToolUse** - Runs after tool execution (auto-fix, notifications)
- **SessionEnd** - Runs when session ends (cleanup, reporting)

For complete hook events documentation, query docs-management skill.

### Step 7: Test Thoroughly

**Run hook tests:**

```bash
bash .claude/hooks/my-new-hook/tests/integration.test.sh
```

**Run all tests:**

```bash
bash .claude/hooks/test-runner.sh
```

**Test manually with sample payload:**

```bash
echo '{"tool": "Write", "file_path": "test.txt"}' | \
  bash .claude/hooks/my-new-hook/bash/my-new-hook.sh
```

**Expected exit codes:**

- `0` - Success (allow operation)
- `1` - Warning (non-blocking)
- `2` - Block operation
- `3` - Error (missing dependencies, config errors)

### Step 8: Document in README

Create `.claude/hooks/my-new-hook/README.md`:

```markdown
# My New Hook

## Purpose

Brief description of what this hook validates or enforces.

## Configuration

- Event: PreToolUse
- Matcher: Write|Edit
- Enforcement: block (configurable)

## How It Works

Explain the validation logic in plain language.

## Configuration Options

Document hook.yaml settings and what they control.

## Examples

### Scenario 1: Blocked Operation

Input: ...
Output: ...

### Scenario 2: Allowed Operation

Input: ...
Output: ...

## Troubleshooting

Common issues and solutions.
```

### Step 9: Restart Claude Code

**IMPORTANT:** New hook registration requires Claude Code restart.

1. Save all files
2. Close Claude Code
3. Restart Claude Code
4. Test hook activation

## Best Practices

### Error Handling

Always check for errors and provide helpful messages:

```bash
if ! check_jq_available; then
    echo "ERROR: jq required. Install from https://jqlang.github.io/jq/" >&2
    exit 3
fi
```

### Config Loading

Load config on each execution (enables hot reload):

```bash
CONFIG="${SCRIPT_DIR}/../config.yaml"
is_hook_enabled "$CONFIG" || exit 0
```

### Logging

Use log levels appropriately:

```bash
log_message "debug" "Processing file: ${FILE_PATH}"
log_message "info" "Hook validation passed"
log_message "warn" "Potential issue detected"
log_message "error" "Critical error occurred"
```

### Testing

Test all scenarios:

1. Hook enabled → Validation passes
2. Hook enabled → Validation fails
3. Hook disabled → Bypasses validation
4. Missing dependencies → Helpful error
5. Invalid config → Graceful failure

## Common Patterns

### Pattern 1: File Path Validation

```bash
FILE_PATH=$(echo "$INPUT" | get_file_path)

if [[ "$FILE_PATH" =~ \.bak$ ]]; then
    echo "ERROR: Backup files not allowed" >&2
    exit 2
fi
```

### Pattern 2: Git Command Detection

```bash
COMMAND=$(echo "$INPUT" | get_command)

if is_git_commit "$COMMAND"; then
    if has_git_flag "$COMMAND" "--no-gpg-sign"; then
        echo "ERROR: GPG signing required" >&2
        exit 2
    fi
fi
```

### Pattern 3: Content Scanning

```bash
NEW_STRING=$(echo "$INPUT" | jq -r '.new_string // ""')

if echo "$NEW_STRING" | grep -qE 'pattern'; then
    echo "ERROR: Pattern not allowed" >&2
    exit 2
fi
```

## Next Steps

After creating your hook:

1. Test thoroughly with various inputs
2. Document edge cases and limitations
3. Add to active hooks inventory
4. Share with team via git commit
5. Monitor for false positives
6. Iterate on enforcement mode if needed

## Reference

- **Shared Utilities:** [../../hooks/shared/](../../../hooks/shared/)
- **Test Framework:** [testing-guide.md](testing-guide.md)
- **Config Guide:** [../configuration/hook-config-guide.md](../configuration/hook-config-guide.md)
- **Official Docs:** Use docs-management skill with keywords "hooks", "PreToolUse", "hook configuration"
