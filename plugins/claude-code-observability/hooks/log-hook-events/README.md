# Log Hook Events

Comprehensive logging for all Claude Code hook events to capture stdin/stdout for observability and troubleshooting.

## Overview

This hook system logs ALL hook events fired by Claude Code, capturing the complete input payload (stdin) for each event. Logs are written in JSON Lines (JSONL) format with daily rotation, enabling efficient parsing, querying, and analysis.

**Purpose:**

- **Observability**: Full visibility into all hook events
- **Troubleshooting**: Debug hook behavior and timing issues
- **Audit trail**: Track all Claude Code interactions
- **Performance analysis**: Monitor hook execution timing

## Hook Events Covered

This system logs all 10 Claude Code hook events:

1. **PreToolUse** - Before tool execution
2. **PermissionRequest** - When permission dialog shown
3. **PostToolUse** - After tool completion
4. **Notification** - When Claude sends notifications
5. **UserPromptSubmit** - When user submits prompt
6. **Stop** - When main agent finishes
7. **SubagentStop** - When subagent finishes
8. **PreCompact** - Before compact operation
9. **SessionStart** - Session start/resume
10. **SessionEnd** - Session end

## Log Format

**Format:** JSON Lines (JSONL) - newline-delimited JSON
**Location:** `.claude/hooks/log-hook-events/logs/{event}/YYYY-MM-DD.jsonl`
**Rotation:** Daily (one file per event per day)

### Log Entry Schema

```json
{
  "timestamp": "2025-11-18T14:32:15.123Z",
  "event": "pretooluse",
  "stdin": {
    "session_id": "abc123",
    "transcript_path": "/path/to/transcript.jsonl",
    "cwd": "/workspace",
    "hook_event_name": "PreToolUse",
    "tool_name": "Write",
    "tool_input": {...}
  },
  "stdout": "",
  "exit_code": 0,
  "duration_ms": 12
}
```

**Fields:**

- `timestamp`: ISO 8601 UTC timestamp
- `event`: Hook event name (lowercase)
- `stdin`: Complete input payload from Claude Code
- `stdout`: Output from hook (typically empty for logging hooks)
- `exit_code`: Hook exit code (0 = success)
- `duration_ms`: Hook execution time in milliseconds

## Configuration

### Master Control

**Disable ALL logging hooks:**

Edit `.claude/hooks/log-hook-events/config.yaml`:

```yaml
enabled: false
```

**Re-enable:**

```yaml
enabled: true
```

### Per-Event Control

**Disable specific events:**

Edit `.claude/hooks/log-hook-events/config.yaml`:

```yaml
events:
  pretooluse:
    enabled: false  # Disable PreToolUse logging
  posttooluse:
    enabled: true   # Keep PostToolUse logging
  # ... other events
```

### Configuration Files

- **`.claude/hooks/config/global.yaml`** - Global enable/disable for all hooks
- **`.claude/hooks/log-hook-events/config.yaml`** - Logging hooks master configuration
- **`.claude/settings.json`** - Hook registrations (requires Claude Code restart to change)

**Note:** Configuration changes take effect immediately on next hook execution. Hook registration changes require Claude Code restart.

## Querying Logs

### Basic Examples

**View today's PreToolUse events:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/2025-11-18.jsonl
```

**Pretty-print with jq:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/2025-11-18.jsonl | jq .
```

**Count events by type:**

```bash
cat .claude/hooks/log-hook-events/logs/*/2025-11-18.jsonl | jq -r '.event' | sort | uniq -c
```

**Find all Write tool uses:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/2025-11-18.jsonl | jq 'select(.stdin.tool_name == "Write")'
```

**Extract specific fields:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/2025-11-18.jsonl | jq '{time: .timestamp, tool: .stdin.tool_name, duration: .duration_ms}'
```

**Filter by time range:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/2025-11-18.jsonl | jq 'select(.timestamp > "2025-11-18T14:00:00Z")'
```

**Average execution time:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/2025-11-18.jsonl | jq -s 'map(.duration_ms) | add/length'
```

### Advanced Queries

**Find slow hook executions (> 100ms):**

```bash
cat .claude/hooks/log-hook-events/logs/*/2025-11-18.jsonl | jq 'select(.duration_ms > 100)'
```

**Track tool usage patterns:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/*.jsonl | jq -r '.stdin.tool_name' | sort | uniq -c | sort -rn
```

**Session analysis:**

```bash
# All events for a specific session
cat .claude/hooks/log-hook-events/logs/*/2025-11-18.jsonl | jq 'select(.stdin.session_id == "abc123")'
```

**Grep for specific content:**

```bash
# Find all events containing "error"
grep -i "error" .claude/hooks/log-hook-events/logs/*/2025-11-18.jsonl | jq .
```

## Log Management

### Manual Cleanup

**Remove logs older than 30 days:**

```bash
find .claude/hooks/log-hook-events/logs -type f -name "*.jsonl" -mtime +30 -delete
```

**Remove logs for specific event:**

```bash
rm .claude/hooks/log-hook-events/logs/pretooluse/2025-10-*.jsonl
```

**Archive old logs:**

```bash
# Compress logs older than 7 days
find .claude/hooks/log-hook-events/logs -type f -name "*.jsonl" -mtime +7 -exec gzip {} \;
```

### Log Size Monitoring

**Check log sizes:**

```bash
du -sh .claude/hooks/log-hook-events/logs/*
```

**Find largest log files:**

```bash
find .claude/hooks/log-hook-events/logs -type f -name "*.jsonl" -exec ls -lh {} \; | sort -k5 -rh | head -10
```

## Troubleshooting

### Hook Not Logging

**1. Check master enabled flag:**

```bash
grep "enabled:" .claude/hooks/log-hook-events/config.yaml
```

**2. Check event-specific flag:**

```bash
grep -A1 "pretooluse:" .claude/hooks/log-hook-events/config.yaml
```

**3. Check global hooks enabled:**

```bash
grep "enabled:" .claude/hooks/config/global.yaml
```

**4. Verify hook registration:**

Check `.claude/settings.json` for hook entries. Changes to settings.json require Claude Code restart.

**5. Check for errors:**

Look for warnings in Claude Code output when hooks execute.

### Missing Log Files

**Logs are created on first event:**

- Log directories exist but are empty until an event fires
- Each event creates its own daily log file on first occurrence

**File permissions:**

- Ensure `.claude/hooks/log-hook-events/logs/` is writable
- Check filesystem permissions if running in restricted environment

### Performance Issues

**Hook execution is very fast (< 100ms typically):**

- If experiencing slowness, check disk I/O
- Consider disabling specific high-frequency events
- Monitor log file sizes

**Reduce logging overhead:**

- Disable events you don't need
- Use event-specific filtering in config.yaml

### Python Dependency

Logging hooks use Python 3.8+ for fast, efficient JSON processing.

**Verify Python is available:**

```bash
python3 --version
# Should show Python 3.8 or newer
```

**If Python is not installed:**

- **Windows:** `winget install Python.Python.3.12`
- **macOS:** `brew install python@3.12`
- **Linux:** `sudo apt install python3` or `sudo yum install python3`

## Architecture

### Vertical Slice Design

All logging hook code, configuration, and logs are encapsulated in `.claude/hooks/log-hook-events/`:

```text
.claude/hooks/log-hook-events/
├── bash/                    # Bash wrapper scripts
│   ├── log-pretooluse.sh    # Event-specific wrappers (call Python)
│   └── ... (10 total)
├── python/                  # Python implementation
│   ├── log_event.py         # Core logging logic
│   └── test_log_event.py    # Tests (pytest)
├── logs/                    # Log output (gitignored)
│   ├── pretooluse/          # One directory per event
│   └── ... (10 total)
├── config.yaml              # Master configuration
├── hook.yaml                # Hook metadata
└── README.md                # This file
```

**Benefits:**

- Easy to locate and manage
- Self-contained feature
- Simple to disable or remove
- Clear separation from validation hooks
- Fast Python-based logging (~5x faster than Bash)

### Hook Execution Order

Logging hooks execute **FIRST** (before validation hooks) to ensure all events are captured even if validation hooks block the operation.

### Performance

**Design goals:**

- Minimal overhead (< 50ms per event)
- Non-blocking (never blocks operations)
- Efficient append-only I/O
- Atomic writes (prevent corruption)
- Safe concurrent writes (multiple Claude Code sessions)

**Measured performance (Python implementation):**

- **Typical execution: 30-40ms** (5x faster than previous Bash implementation)
- Log append: < 5ms
- JSON formatting: < 2ms (built-in Python json module)
- Config caching: ~0ms (cached in environment variables)

**Previous Bash performance:** ~166ms (for comparison)

## Future Enhancements

### Planned Features (Out of Scope)

1. **Log Management Scripts**
   - `list-logs.sh` - List available logs by event/date
   - `query-logs.sh` - Query logs with jq filters
   - `cleanup-logs.sh` - Automatic cleanup based on retention policy
   - `stats-logs.sh` - Generate statistics (event counts, timing, etc.)

2. **Enhanced Features**
   - Size-based rotation (in addition to daily)
   - Automatic compression of old logs
   - Log streaming/tailing utilities
   - Dashboard for log visualization
   - Structured search and indexing

3. **Integration**
   - Export to external log aggregation systems
   - Prometheus metrics export
   - Real-time monitoring alerts

## Related Documentation

- **Hooks System:** `.claude/hooks/README.md`
- **Shared Utilities:** `.claude/hooks/shared/config-utils.sh`
- **Hooks Meta Skill:** `.claude/skills/hooks-meta/SKILL.md`
- **Official Hooks Documentation:** Via official-docs skill (keywords: "hooks", "PreToolUse", "PostToolUse")

## Version History

- **v1.1.0** (2025-11-24) - Audit improvements
  - Fixed master switch config parsing bug
  - Added VALID_EVENTS constant for event validation
  - Improved YAML parsing with proper nested key support
  - Removed 143 lines of dead code from logging-utils.sh
  - Increased hook timeouts from 2s to 5s for reliability
  - Added documentation for architecture decisions (cache TTL, multi-process safety)

- **v1.0.0** (2025-11-18) - Initial implementation
  - All 10 hook events supported
  - JSONL format with daily rotation
  - Master and per-event enable/disable
  - Comprehensive query examples

## Last Verified

**Date:** 2025-11-24

**Status:** Production-ready

**Dependencies:**

- Python 3.8+ (tested with 3.12, 3.14)
- Bash 4.0+
- jq (recommended for log queries)
- Git Bash (Windows)
