# Plugin Hook Utilities Reference

This reference documents the standard pattern for plugin authors to create **configurable hooks** that consumers can enable, disable, and customize via environment variables.

## Overview

Plugin hooks are defined in `hooks/hooks.json` and automatically merged when a plugin is enabled. Unlike repository-local hooks (`.claude/hooks/`), plugin hooks use **environment variables** for consumer control, set via the `env` section of `settings.json`.

## Environment Variable Convention

Use this naming convention for all plugin hooks:

| Variable Pattern | Purpose | Values |
| ---------------- | ------- | ------ |
| `CLAUDE_HOOK_{NAME}_ENABLED` | Enable/disable hook | `1`/`true` (enabled), `0`/`false` (disabled) |
| `CLAUDE_HOOK_ENFORCEMENT_{NAME}` | Control enforcement behavior | `block`, `warn`, `log` |
| `CLAUDE_HOOK_LOG_LEVEL` | Global logging verbosity | `debug`, `info`, `warn`, `error` |

**Naming `{NAME}`:** Use SCREAMING_SNAKE_CASE matching the hook's purpose. Examples:

- `MARKDOWN_LINT` for markdown linting hook
- `SECRET_SCAN` for secret scanning hook
- `GPG_SIGNING` for GPG signing enforcement

**Default Behavior:** Hooks should define a sensible default (enabled or disabled) and only change behavior when the environment variable is explicitly set.

## Standard Exit Codes

All hooks must use these exit codes (per official Claude Code documentation):

| Exit Code | Meaning | When to Use |
| --------- | ------- | ----------- |
| `0` | Allow/Success | No issues, or `log` enforcement mode |
| `1` | Warning | Non-blocking issue, or `warn` enforcement mode |
| `2` | Block | Prevents tool execution, `block` enforcement mode |
| `3` | Error | Script failure (non-blocking) |

## Implementation Template

### Basic Hook Script

```bash
#!/usr/bin/env bash
# my-hook.sh - Description of what this hook does
#
# Event: PreToolUse | PostToolUse | UserPromptSubmit
# Matcher: ToolName | ToolPattern
# Purpose: Brief description
#
# Environment Variables:
#   CLAUDE_HOOK_MY_HOOK_ENABLED - Set to 0/false to disable (default: enabled)
#   CLAUDE_HOOK_ENFORCEMENT_MY_HOOK - block, warn (default), or log
#   CLAUDE_HOOK_LOG_LEVEL - debug, info (default), warn, or error

set -euo pipefail

# Plugin root with fallback for local testing
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

#=============================================================================
# Configuration Check - Early Exit if Disabled
#=============================================================================

# Check if hook is enabled via environment variable (default: enabled)
# To disable: CLAUDE_HOOK_MY_HOOK_ENABLED=0 or CLAUDE_HOOK_MY_HOOK_ENABLED=false
if [ "${CLAUDE_HOOK_MY_HOOK_ENABLED:-1}" = "0" ] || \
   [ "${CLAUDE_HOOK_MY_HOOK_ENABLED:-true}" = "false" ]; then
    exit 0  # Silently skip
fi

#=============================================================================
# Logging Utility
#=============================================================================

HOOK_LOG_LEVEL="${CLAUDE_HOOK_LOG_LEVEL:-info}"

log_message() {
    local level="$1"
    local message="$2"

    # Simple log level filtering (debug < info < warn < error)
    case "$HOOK_LOG_LEVEL" in
        debug) ;;
        info)  [ "$level" = "debug" ] && return ;;
        warn)  [ "$level" = "debug" ] || [ "$level" = "info" ] && return ;;
        error) [ "$level" != "error" ] && return ;;
    esac

    echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] [${level^^}] $message" >&2
}

#=============================================================================
# Main Hook Logic
#=============================================================================

# Read JSON input from stdin (for PreToolUse/PostToolUse hooks)
INPUT=$(cat)

# Extract relevant fields (requires jq)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // .tool // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')

log_message "debug" "my-hook: tool=$TOOL, file_path=$FILE_PATH"

# Your validation/processing logic here
# ...

# Example: Check for a violation
VIOLATION_FOUND=false
# ... detection logic ...

if [ "$VIOLATION_FOUND" = "true" ]; then
    # Load enforcement mode (default: warn)
    ENFORCEMENT="${CLAUDE_HOOK_ENFORCEMENT_MY_HOOK:-warn}"

    ERROR_MESSAGE="Description of the violation"

    case "$ENFORCEMENT" in
        block)
            echo "ERROR: $ERROR_MESSAGE" >&2
            log_message "info" "my-hook: Blocking operation (exit 2)"
            exit 2
            ;;
        warn)
            echo "WARNING: $ERROR_MESSAGE" >&2
            log_message "info" "my-hook: Warning issued (exit 1)"
            exit 1
            ;;
        log)
            log_message "info" "my-hook: Violation logged but allowing (exit 0)"
            exit 0
            ;;
        *)
            # Default to warn (non-blocking)
            echo "WARNING: $ERROR_MESSAGE" >&2
            exit 1
            ;;
    esac
fi

# No violation - allow operation
log_message "debug" "my-hook: No issues found, allowing"
exit 0
```

### Shared Utilities Pattern

For plugins with multiple hooks, create shared utilities:

**scripts/shared/config-utils.sh:**

```bash
#!/usr/bin/env bash
# config-utils.sh - Shared configuration utilities for plugin hooks

set -euo pipefail

HOOK_LOG_LEVEL="${CLAUDE_HOOK_LOG_LEVEL:-info}"

# Log message based on log level
log_message() {
    local level="$1"
    local message="$2"

    case "$HOOK_LOG_LEVEL" in
        debug) ;;
        info)  [ "$level" = "debug" ] && return ;;
        warn)  [ "$level" = "debug" ] || [ "$level" = "info" ] && return ;;
        error) [ "$level" != "error" ] && return ;;
    esac

    echo "[$(date -u +"%Y-%m-%d %H:%M:%S UTC")] [${level^^}] $message" >&2
}

# Check if hook is enabled via environment variable
# Usage: is_hook_enabled "HOOK_NAME" ["default_enabled"]
# Examples:
#   is_hook_enabled "MY_HOOK" || exit 0          # Default enabled
#   is_hook_enabled "MY_HOOK" "false" || exit 0  # Default disabled
is_hook_enabled() {
    local hook_name="$1"
    local default_enabled="${2:-true}"
    local env_var="CLAUDE_HOOK_${hook_name}_ENABLED"
    local value="${!env_var:-}"

    # If explicitly set, use that value
    if [ -n "$value" ]; then
        if [ "$value" = "1" ] || [ "$value" = "true" ]; then
            return 0  # Enabled
        else
            return 1  # Disabled
        fi
    fi

    # Use default
    if [ "$default_enabled" = "true" ]; then
        return 0
    else
        return 1
    fi
}

# Load enforcement mode for a hook
# Usage: mode=$(load_enforcement_mode "HOOK_NAME" "default_mode")
load_enforcement_mode() {
    local hook_name="$1"
    local default="${2:-warn}"
    local env_var="CLAUDE_HOOK_ENFORCEMENT_${hook_name}"

    echo "${!env_var:-$default}"
}

# Standard exit codes
EXIT_SUCCESS=0
EXIT_WARN=1
EXIT_BLOCK=2
EXIT_ERROR=3
```

**Usage in hooks:**

```bash
#!/usr/bin/env bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "${PLUGIN_ROOT}/scripts/shared/config-utils.sh"

# Check if enabled
is_hook_enabled "MY_HOOK" || exit 0

# Get enforcement mode
ENFORCEMENT=$(load_enforcement_mode "MY_HOOK" "warn")

# ... hook logic ...
```

## hooks.json Configuration

Document configurable hooks in your `hooks/hooks.json` description:

```json
{
  "description": "Plugin hooks with consumer-configurable behavior via env vars",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/hooks/my-hook.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

## Documentation Requirements

Plugin authors should document hooks in:

1. **Plugin README.md:**

    ```markdown
    ## Hooks

    This plugin includes the following hooks:

    ### my-hook (PostToolUse)

    Validates files after Write/Edit operations.

    **Configuration:**
    - `CLAUDE_HOOK_MY_HOOK_ENABLED=0` - Disable this hook (default: enabled)
    - `CLAUDE_HOOK_ENFORCEMENT_MY_HOOK=warn` - Set to `block`, `warn`, or `log`
    ```

2. **Hook script header comments** (shown in template above)

3. **hooks.json description field**

## Best Practices

1. **Always check enabled state first** - Exit early with code 0 if disabled
2. **Default to non-blocking** - Use `warn` as default enforcement mode
3. **Log at appropriate levels** - Use `debug` for verbose output, `info` for normal operation
4. **Handle missing dependencies gracefully** - Exit with warning, not error
5. **Document all env vars** - In README, hook header, and hooks.json
6. **Use SCREAMING_SNAKE_CASE** - For env var names (e.g., `CLAUDE_HOOK_MY_HOOK_ENABLED`)
7. **Test with all enforcement modes** - Verify `block`, `warn`, and `log` all work correctly
8. **Choose sensible defaults** - Essential hooks default enabled; opt-in hooks default disabled

## Example: Real Implementation

See the code-quality plugin's markdown-lint hook for a production example:

- Hook script: `plugins/code-quality/scripts/hooks/markdown-lint.sh`
- Shared utilities: `plugins/code-quality/scripts/shared/config-utils.sh`
- hooks.json: `plugins/code-quality/hooks/hooks.json`

## Related References

- [Consumer Configuration Reference](plugin-hook-consumer-config.md) - How consumers configure these hooks
- Official Claude Code hooks documentation (via docs-management skill)
