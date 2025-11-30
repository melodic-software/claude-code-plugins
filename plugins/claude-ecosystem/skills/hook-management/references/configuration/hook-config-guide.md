# Hook Configuration Guide

**Last Updated:** 2025-11-25

## Overview

This guide covers hook configuration management, including global settings, per-hook configuration, and configuration file formats.

## Configuration Hierarchy

### 1. Global Configuration

**File:** `.claude/hooks/config/global.yaml`

Controls all hooks with shared settings:

- Master enabled/disabled switch
- Shared patterns (backup extensions, path patterns, etc.)
- Global thresholds and settings
- Exit codes
- Log levels

### 2. Per-Hook Configuration (User Settings)

**File:** `.claude/hooks/<hook-name>/config.yaml`

Controls individual hook runtime behavior:

- Hook-specific enabled/disabled toggle
- Enforcement mode (block, warn, log)
- Exit codes
- Hook-specific patterns
- Custom messages

**Hot reload:** Changes take effect immediately on next hook execution.

### 3. Per-Hook Metadata (Reference Only)

**File:** `.claude/hooks/<hook-name>/hook.yaml`

Contains hook metadata and implementation details:

- Hook name, version, description
- Implementation details (entry points, handlers, minimum versions)
- Implementation selection strategy

**Note:** This file is for reference and documentation purposes. Runtime behavior is controlled by `config.yaml`.

## Configuration Format

**All configuration uses YAML:**

- Human-friendly format
- Supports comments for documentation
- Excellent for manual editing
- Hierarchical structure

**Example YAML structure:**

```yaml
# This is a comment explaining the setting
name: hook-name
version: 1.0.0
enabled: true
enforcement: block

patterns:
  excluded_paths:
    - 'docs/examples'
    - 'tests/fixtures'

messages:
  violation: "Custom error message here"
  suggestion: "How to fix this issue"
```

## Hot Reload vs Claude Code Restart

### Hot Reload (Immediate Effect)

These changes take effect on the next hook execution without restarting Claude Code:

- `enabled` state (global or per-hook)
- `enforcement` mode
- `patterns` arrays
- `messages` content
- `timeout_seconds`
- `log_level`

### Requires Restart

These changes require Claude Code restart:

- Hook registration in `.claude/settings.json`
- Matchers (which tools trigger hooks)
- Command paths or entry points

## Master Control

### Disable ALL Hooks

Edit `.claude/hooks/config/global.yaml`:

```yaml
enabled: false
```

### Re-enable All Hooks

```yaml
enabled: true
```

Changes take effect immediately on next hook execution.

## Per-Hook Control

### Disable Specific Hook

Edit the hook's `config.yaml` (e.g., `.claude/hooks/prevent-backup-files/config.yaml`):

```yaml
enabled: false
```

Changes take effect immediately on next hook execution.

### Change Enforcement Level

```yaml
enforcement: warn  # Options: block, warn, log
```

**Enforcement levels:**

- **block** - Prevents operation entirely (exit code 2)
- **warn** - Shows warning but allows operation (exit code 1)
- **log** - Logs issue but allows operation silently (exit code 0 with stderr output)

### Switch Implementation

To switch from bash to python implementation:

1. Update `.claude/hooks/<hook-name>/config.yaml`:

   ```yaml
   implementations:
     active: python
   ```

2. Update `.claude/settings.json` to point to new entry point
3. Restart Claude Code (registration changes require restart)

## Configuration Files Reference

### Global Config Structure

```yaml
# .claude/hooks/config/global.yaml

# Master switch for all hooks
enabled: true

# Global logging
log_level: info  # debug, info, warn, error

# Execution settings
execution:
  timeout_seconds: 30
  max_retries: 0

# Shared patterns (all hooks can reference)
patterns:
  backup_extensions:
    - '.bak'
    - '.backup'
    - '.tmp'
    - '~'

  absolute_path_indicators:
    - 'drive_letters: [A-Z]:\\'
    - 'unix_absolute: ^/'

  excluded_paths:
    - '.claude/temp'
    - 'node_modules'
    - '.git'

# Exit codes (standard across all hooks)
exit_codes:
  success: 0
  warn: 1
  block: 2
  error: 3
```

### Per-Hook Config Structure (config.yaml)

```yaml
# .claude/hooks/<hook-name>/config.yaml
# User-facing configuration - changes take effect immediately

# Hook control
enabled: true

# Enforcement mode determines exit code behavior:
# - block: exit 2 (prevents operation)
# - warn: exit 1 (allows but warns)
# - log: exit 0 (silent logging)
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
  additional_extensions: []
  excluded_paths:
    - '.git'
    - 'node_modules'

# Custom messages
messages:
  violation: "Violation detected: {{details}}"
  suggestion: "How to fix this issue"
  documentation: "See CLAUDE.md for rationale"
```

### Per-Hook Metadata Structure (hook.yaml)

```yaml
# .claude/hooks/<hook-name>/hook.yaml
# Reference metadata - for documentation, not runtime behavior

name: hook-name
version: 1.0.0
description: Brief description of what this hook does

# Implementation details (reference only)
implementations:
  bash:
    entry_point: bash/hook-name.sh
    handler: main
    minimum_version: "4.0"
    available: true
  python:
    entry_point: python/hook_name.py
    handler: validate
    minimum_version: "3.8"
    dependencies: python/requirements.txt
    available: false

# Selection strategy (reference only)
selection:
  strategy: preference_order
  preference_order: [bash]
  active: bash

# Execution settings
timeout_seconds: 10
concurrent_safe: true
```

## Configuration Best Practices

### 1. Use Comments Liberally

```yaml
# This controls whether the hook runs at all
enabled: true

# Enforcement mode determines exit code behavior:
# - block: exit 2 (prevents operation)
# - warn: exit 1 (allows but warns)
# - log: exit 0 (silent logging)
enforcement: block
```

### 2. Keep Patterns DRY

Reference global patterns instead of duplicating:

```yaml
# In hook.yaml - reference global patterns
patterns:
  # Extend global backup extensions with hook-specific additions
  additional_extensions:
    - '.hook-specific-ext'
```

### 3. Version Your Configs

```yaml
name: hook-name
version: 1.2.0  # Increment when making breaking changes
```

### 4. Document Decisions

```yaml
# Changed from 'block' to 'warn' on 2025-11-18 to reduce friction
# during development phase. Will change back to 'block' once stable.
enforcement: warn
```

## Testing Configuration Changes

After modifying configuration:

1. **Verify YAML syntax** (use online validator if unsure)

2. **Test hook directly:**

   ```bash
   echo '{"tool": "Write", "file_path": "test.md"}' | \
     bash .claude/hooks/<hook-name>/bash/<hook-name>.sh
   ```

3. **Run integration tests:**

   ```bash
   bash .claude/hooks/<hook-name>/tests/integration.test.sh
   ```

4. **Check logs** (increase log_level to debug if needed)

## Advanced Configuration

### Conditional Patterns

Some hooks support conditional pattern matching:

```yaml
patterns:
  # Only apply to certain file types
  file_extensions: ['.md', '.txt']

  # Exclude certain directories
  excluded_paths:
    - 'tests/fixtures'
    - 'docs/examples'

  # Custom regex patterns
  custom_patterns:
    - 'pattern1'
    - 'pattern2'
```

### Message Templating

Use `{{variable}}` syntax for dynamic messages:

```yaml
messages:
  violation: "Blocked: {{file_path}} matches pattern {{pattern}}"
  suggestion: "Remove {{details}} from your changes"
```

Variables depend on hook implementation. See hook's README for available variables.

## Troubleshooting Configuration Issues

### YAML Syntax Errors

**Symptom:** Hook doesn't run or crashes

**Solution:**

- Use online YAML validator
- Check indentation (use spaces, not tabs)
- Ensure quotes match (start and end)

### Config Changes Not Taking Effect

**Symptom:** Modified config but behavior unchanged

**Solution:**

1. Verify file was saved
2. Check YAML syntax is valid
3. Ensure global enabled is true
4. Test hook directly to bypass caching

### Hook Registration Changes

**Symptom:** New matchers or command paths not working

**Solution:**

- Restart Claude Code (registration changes require restart)
- Verify `.claude/settings.json` syntax is valid JSON
- Check Claude Code logs for registration errors

For more troubleshooting, see [../troubleshooting/common-issues.md](../troubleshooting/common-issues.md).
