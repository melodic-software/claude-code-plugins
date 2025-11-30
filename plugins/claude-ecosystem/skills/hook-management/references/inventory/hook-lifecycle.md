# Hook Lifecycle Management

**Last Updated:** 2025-11-24

## Overview

This document covers common workflows for managing hooks throughout their lifecycle: disabling, enabling, modifying enforcement, switching implementations, and viewing activity.

## Temporarily Disable All Hooks

Edit `.claude/hooks/config/global.yaml`:

```yaml
enabled: false
```

To re-enable, set back to `true`. Changes take effect immediately.

**Use case:** Temporarily bypass all hooks for emergency fixes or testing.

## Disable Specific Hook

Edit hook's `config.yaml` (e.g., `.claude/hooks/prevent-backup-files/config.yaml`):

```yaml
enabled: false
```

Changes take effect immediately.

**Use case:** Disable one hook without affecting others.

## Change from Block to Warn

Edit hook's `config.yaml`:

```yaml
enforcement: warn  # Options: block, warn, log, ask
```

Changes take effect immediately.

**Enforcement modes:**

- **block** - Prevents operation entirely
- **warn** - Shows warning but allows operation
- **log** - Logs issue but allows operation silently
- **ask** - Prompts user for decision (specific hooks only)

## Switch Hook Implementation

Edit hook's `config.yaml`:

```yaml
implementations:
  active: python  # Switch from bash to python
```

Also update `.claude/settings.json` to point to new entry point, then restart Claude Code.

**Use case:** Migrate from bash to python/typescript for better performance or features.

**Important:** Changing implementation language requires Claude Code restart.

## Add Exclusion Pattern

### Hook-Specific Exclusion

Edit hook's `config.yaml`:

```yaml
patterns:
  excluded_paths:
    - 'docs/examples'
    - 'tests/fixtures'
```

### Global Exclusion (All Hooks)

Edit `config/global.yaml` (affects all hooks):

```yaml
patterns:
  excluded_paths:
    - '.claude/temp'
    - 'node_modules'
```

Changes take effect immediately.

**Use case:** Exclude certain directories from hook validation (test data, examples, temporary files).

## View Hook Activity

Increase log level in `.claude/hooks/config/global.yaml`:

```yaml
log_level: debug  # Options: debug, info, warn, error
```

Changes take effect immediately. Hook activity will be logged to stderr/Claude Code terminal.

**Log levels:**

- **debug** - Verbose logging (all operations)
- **info** - Standard logging (hook execution, decisions)
- **warn** - Warnings only (issues encountered)
- **error** - Errors only (critical failures)

## Run Tests

```bash
# All tests
bash .claude/hooks/test-runner.sh

# Specific hook
bash .claude/hooks/prevent-backup-files/tests/integration.test.sh

# Specific utility
bash .claude/hooks/shared/json-utils.test.sh
```

**Use case:** Verify hooks work correctly after configuration changes or upgrades.

## Configuration Change Timing

### Immediate Effect (No Restart)

Changes to these take effect on next hook execution:

- Hook enabled/disabled state
- Enforcement mode (block, warn, log, ask)
- Patterns (excluded_paths, etc.)
- Messages
- Timeouts
- Log levels

### Requires Restart

Changes to these require Claude Code restart:

- Hook registration (`.claude/settings.json` hooks section)
- Matchers (which tools trigger the hook)
- Implementation entry point (switching from bash to python)

## Hook Removal

To permanently remove a hook:

1. **Remove from settings.json:**

   ```bash
   # Edit .claude/settings.json and remove hook entry
   ```

2. **Delete hook directory:**

   ```bash
   rm -rf .claude/hooks/<hook-name>
   ```

3. **Restart Claude Code** for registration change to take effect

**Caution:** Deleting a hook directory removes all its code, tests, and configuration. Ensure you have backups if you might need it later.

## Hook Update Workflow

To update a hook's logic:

1. **Make code changes** in `bash/<hook-name>.sh` (or python/typescript)
2. **Update tests** in `tests/integration.test.sh`
3. **Run tests** to verify changes work:

   ```bash
   bash .claude/hooks/<hook-name>/tests/integration.test.sh
   ```

4. **Update version** in `hook.yaml` (metadata file):

   ```yaml
   version: 1.1.0  # Increment version
   ```

5. **Test manually** with sample payload if needed
6. **Commit changes** to version control

Changes to hook code take effect immediately on next hook execution (no restart needed).

## Troubleshooting Hook Changes

If configuration changes don't seem to take effect:

1. **Verify YAML syntax** (use online YAML validator if unsure)
2. **Check file was saved** (reload file in editor to confirm)
3. **Test hook directly:**

   ```bash
   echo '{"tool": "Write", "file_path": "test.md"}' | \
     bash .claude/hooks/<hook-name>/bash/<hook-name>.sh
   ```

4. **Check global enabled state** (might be disabled globally)
5. **Increase log level** to debug to see what's happening

For more troubleshooting guidance, see [../troubleshooting/common-issues.md](../troubleshooting/common-issues.md).
