# Plugin Hook Consumer Configuration Reference

This reference explains how **plugin consumers** can control plugin hooks via environment variables in `settings.json`.

## Overview

When you install a plugin, its hooks are automatically merged and run during your Claude Code sessions. Claude Code doesn't provide native per-hook disable controls, but plugins that follow the configurable hooks pattern allow you to control their behavior via environment variables.

## How It Works

1. Plugin hooks check for specific environment variables at runtime
2. You set these variables in your `.claude/settings.json` or `.claude/settings.local.json`
3. Claude Code reads the `env` section and applies these variables to every session
4. Plugin hooks read the variables and adjust their behavior accordingly

## Configuration Location

| File | Scope | Committed to Git? |
| ---- | ----- | ----------------- |
| `.claude/settings.json` | Project-wide | Yes (shared with team) |
| `.claude/settings.local.json` | Personal | No (gitignored) |
| `~/.claude/settings.json` | User-wide | N/A (your home directory) |

**Recommendation:** Use `.claude/settings.local.json` for personal preferences that shouldn't affect teammates.

## Environment Variable Pattern

Configurable plugin hooks use this naming convention:

| Variable | Values | Purpose |
| -------- | ------ | ------- |
| `CLAUDE_HOOK_DISABLED_<NAME>` | `1` or `true` | Disable specific hook |
| `CLAUDE_HOOK_ENFORCEMENT_<NAME>` | `block`, `warn`, `log` | Control enforcement |
| `CLAUDE_HOOK_LOG_LEVEL` | `debug`, `info`, `warn`, `error` | Logging verbosity |

**`<NAME>`** is the hook identifier in SCREAMING_SNAKE_CASE (e.g., `MARKDOWN_LINT`, `SECRET_SCAN`).

## Configuration Examples

### Disable a Specific Hook

```json
{
  "env": {
    "CLAUDE_HOOK_DISABLED_MARKDOWN_LINT": "1"
  }
}
```

### Change Enforcement Mode

By default, most hooks use `warn` (non-blocking). You can change this:

```json
{
  "env": {
    "CLAUDE_HOOK_ENFORCEMENT_MARKDOWN_LINT": "log"
  }
}
```

Enforcement modes:

- **`block`** - Prevents the operation (exit code 2)
- **`warn`** - Shows warning but allows operation (exit code 1)
- **`log`** - Silently logs but allows operation (exit code 0)

### Enable Debug Logging

For troubleshooting hook behavior:

```json
{
  "env": {
    "CLAUDE_HOOK_LOG_LEVEL": "debug"
  }
}
```

### Complete Example

```json
{
  "env": {
    "CLAUDE_HOOK_DISABLED_MARKDOWN_LINT": "1",
    "CLAUDE_HOOK_ENFORCEMENT_SECRET_SCAN": "block",
    "CLAUDE_HOOK_ENFORCEMENT_GPG_SIGNING": "warn",
    "CLAUDE_HOOK_LOG_LEVEL": "info"
  }
}
```

## Finding Hook Names

Check the plugin's documentation for available hooks and their environment variable names. Typically found in:

1. **Plugin README** - Look for "Hooks" or "Configuration" section
2. **Hook script header** - Comments at the top of the hook script
3. **hooks.json** - The `description` field may mention configurable options

### Example: code-quality Plugin

The `code-quality` plugin provides:

| Hook | Disable Variable | Enforcement Variable |
| ---- | ---------------- | -------------------- |
| markdown-lint | `CLAUDE_HOOK_DISABLED_MARKDOWN_LINT` | `CLAUDE_HOOK_ENFORCEMENT_MARKDOWN_LINT` |

## Settings Precedence

Environment variables follow Claude Code's settings precedence (highest to lowest):

1. **Enterprise managed policies** (`managed-settings.json`) - Cannot be overridden
2. **Command line arguments** - Temporary overrides
3. **Local project settings** (`.claude/settings.local.json`) - Personal preferences
4. **Shared project settings** (`.claude/settings.json`) - Team settings
5. **User settings** (`~/.claude/settings.json`) - Global defaults

This means:

- `.claude/settings.local.json` overrides `.claude/settings.json`
- Enterprise policies can enforce hooks that users cannot disable

## Global Hook Control

Claude Code also provides a global kill switch:

```json
{
  "disableAllHooks": true
}
```

This disables **all** hooks (project hooks, user hooks, and plugin hooks). Use sparingly.

## Troubleshooting

### Hook Still Running After Disabling

1. **Check variable name** - Must match exactly (case-sensitive)
2. **Check value** - Must be `"1"` or `"true"` (as strings in JSON)
3. **Restart session** - Settings are read at session start
4. **Check precedence** - Enterprise policies may override your settings

### Hook Not Working as Expected

1. Enable debug logging: `"CLAUDE_HOOK_LOG_LEVEL": "debug"`
2. Check stderr output for hook messages
3. Verify the plugin follows the configurable hooks pattern

### Finding Which Hooks Are Active

Run `/hooks` in Claude Code to see active hooks from all sources (project, user, plugins).

## Comparison: Plugin Hooks vs Local Hooks

| Aspect | Plugin Hooks | Local Hooks (`.claude/hooks/`) |
| ------ | ------------ | ------------------------------ |
| Configuration | Environment variables | YAML config files |
| Control | Via `settings.json` `env` section | Via `config.yaml` per hook |
| Scope | All projects using the plugin | Single repository |
| Enable/Disable | `CLAUDE_HOOK_DISABLED_*` env var | `enabled: false` in config.yaml |

## Related References

- [Plugin Hook Utilities Reference](plugin-hook-utilities.md) - For plugin authors
- Official Claude Code hooks documentation (via docs-management skill)
- Official Claude Code settings documentation (via docs-management skill)
