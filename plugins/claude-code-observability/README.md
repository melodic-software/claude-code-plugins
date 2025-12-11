# Claude Code Observability Plugin

Observability hooks for Claude Code: comprehensive event logging, performance metrics, and session diagnostics.

## Overview

This plugin provides full observability into Claude Code hook execution without modifying behavior. All hooks are purely observational - they log events but never block operations or enforce rules.

**Key Benefits:**

- **Full audit trail** - Track all Claude Code interactions
- **Performance analysis** - Monitor hook execution timing via `duration_ms`
- **Configurable verbosity** - Choose between minimal, summary, or full logging
- **Size-based rotation** - Automatic log rotation to prevent unbounded growth
- **Optional by design** - Enable/disable via environment variables

## Installation

```bash
/plugin install claude-code-observability@claude-code-plugins
```

## Quick Start

Enable logging by setting the master toggle in your `.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_HOOK_LOG_EVENTS_ENABLED": "1"
  }
}
```

Logs are written to: `.claude/logs/hooks/events-YYYY-MM-DD.jsonl`

## Configuration

All configuration is via environment variables (set in `.claude/settings.json` `env` section):

### Master Control

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_HOOK_LOG_EVENTS_ENABLED` | Master enable/disable | `0` (disabled) |
| `CLAUDE_HOOK_LOG_DEBUG` | Show errors in stderr | `0` |

### Per-Event Toggles

Disable specific events while keeping others enabled:

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_HOOK_LOG_PRETOOLUSE_ENABLED` | Log PreToolUse events | `1` |
| `CLAUDE_HOOK_LOG_POSTTOOLUSE_ENABLED` | Log PostToolUse events | `1` |
| `CLAUDE_HOOK_LOG_USERPROMPTSUBMIT_ENABLED` | Log UserPromptSubmit events | `1` |
| `CLAUDE_HOOK_LOG_STOP_ENABLED` | Log Stop events | `1` |
| `CLAUDE_HOOK_LOG_SUBAGENTSTOP_ENABLED` | Log SubagentStop events | `1` |
| `CLAUDE_HOOK_LOG_SESSIONSTART_ENABLED` | Log SessionStart events | `1` |
| `CLAUDE_HOOK_LOG_SESSIONEND_ENABLED` | Log SessionEnd events | `1` |
| `CLAUDE_HOOK_LOG_PRECOMPACT_ENABLED` | Log PreCompact events | `1` |
| `CLAUDE_HOOK_LOG_NOTIFICATION_ENABLED` | Log Notification events | `1` |
| `CLAUDE_HOOK_LOG_PERMISSIONREQUEST_ENABLED` | Log PermissionRequest events | `1` |

### Verbosity Levels

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_HOOK_LOG_VERBOSITY` | Output detail level | `summary` |

**Verbosity options:**

- **`minimal`** (~200 bytes/entry): timestamp, event, session_id, tool_name, duration_ms
- **`summary`** (~500 bytes/entry): minimal + transcript_path, tool_use_id, cwd, permission_mode
- **`full`** (1-50KB/entry): Complete input payload with all details

### Log Rotation

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_HOOK_LOG_ROTATION_ENABLED` | Enable size-based rotation | `1` |
| `CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB` | Max file size before rotation | `10` |

When a log file exceeds the max size, a new file is created: `events-2025-12-11-001.jsonl`

### Log Retention

| Variable | Description | Default |
|----------|-------------|---------|
| `CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS` | Default cleanup retention | `30` |

Used by the `/cleanup-hook-logs` command.

## Log Format

Logs are stored as JSON Lines (one JSON object per line) in daily files.

**Location:** `.claude/logs/hooks/events-YYYY-MM-DD.jsonl`

### Sample Log Entries

**Minimal verbosity:**

```json
{"timestamp":"2025-12-11T16:13:15.464Z","event":"pretooluse","session_id":"abc-123","tool_name":"Bash","duration_ms":2.45}
```

**Summary verbosity:**

```json
{"timestamp":"2025-12-11T16:13:15.464Z","event":"pretooluse","session_id":"abc-123","tool_name":"Bash","duration_ms":2.45,"transcript_path":"/path/to/transcript.jsonl","tool_use_id":"toolu_01xyz","cwd":"/workspace","permission_mode":"bypassPermissions"}
```

**Full verbosity:**

```json
{"timestamp":"2025-12-11T16:13:15.464Z","event":"pretooluse","session_id":"unknown","input":{"session_id":"abc-123","tool_name":"Bash","tool_input":{"command":"git status"},...},"duration_ms":2.45,"environment":{"CLAUDE_PROJECT_DIR":"/workspace"}}
```

## Events Logged

All 10 Claude Code hook events are captured:

| Event | Description |
|-------|-------------|
| PreToolUse | Before tool execution |
| PermissionRequest | When permission dialog shown |
| PostToolUse | After tool completion |
| Notification | When Claude sends notifications |
| UserPromptSubmit | When user submits prompt |
| Stop | When main agent finishes |
| SubagentStop | When subagent finishes |
| PreCompact | Before compact operation |
| SessionStart | Session start/resume |
| SessionEnd | Session end |

## Querying Logs

**View today's events:**

```bash
cat .claude/logs/hooks/events-$(date +%Y-%m-%d).jsonl | jq .
```

**Count events by type:**

```bash
cat .claude/logs/hooks/events-*.jsonl | jq -r '.event' | sort | uniq -c
```

**Find all Write tool uses:**

```bash
cat .claude/logs/hooks/events-*.jsonl | jq 'select(.tool_name == "Write")'
```

**Find slow operations (> 10ms):**

```bash
cat .claude/logs/hooks/events-*.jsonl | jq 'select(.duration_ms > 10)'
```

**Summary of events by session:**

```bash
cat .claude/logs/hooks/events-*.jsonl | jq -r '.session_id' | sort | uniq -c | sort -rn
```

## Commands

### /cleanup-hook-logs

Delete old log files to free disk space:

```bash
# Delete logs older than 30 days (default)
/cleanup-hook-logs

# Delete logs older than 7 days
/cleanup-hook-logs 7

# Preview what would be deleted
/cleanup-hook-logs --dry-run
```

## Recommended Configuration

Add to your `.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_HOOK_LOG_EVENTS_ENABLED": "1",
    "CLAUDE_HOOK_LOG_VERBOSITY": "summary",
    "CLAUDE_HOOK_LOG_ROTATION_ENABLED": "1",
    "CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB": "10",
    "CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS": "30"
  }
}
```

## Uninstallation

To completely disable all observability hooks (zero overhead):

```bash
/plugin uninstall claude-code-observability
```

## Dependencies

- Python 3.6+ (uses only standard library)
- jq (recommended for log queries)

## Design Principles

1. **Never block Claude Code** - All exceptions caught, always exits 0
2. **Fail silently** - Logging failures don't impact user experience
3. **No dependencies** - Uses only Python standard library
4. **Cross-platform** - Works on Windows, macOS, and Linux
5. **Configurable** - All settings via environment variables

## License

MIT
