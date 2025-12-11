---
description: Clean up old Claude Code hook log files based on retention policy
---

# Cleanup Hook Logs

Delete old hook log files to free up disk space.

## Usage

```bash
# Delete logs older than 30 days (default)
/cleanup-hook-logs

# Delete logs older than 7 days
/cleanup-hook-logs 7

# Preview what would be deleted (dry run)
/cleanup-hook-logs --dry-run

# Delete logs older than 14 days with preview first
/cleanup-hook-logs 14 --dry-run
```

## Arguments

- First argument (optional): Number of days - delete logs older than N days (default: 30, or from `CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS`)
- `--dry-run` or `-n`: Preview what would be deleted without actually deleting

## Task

Run the cleanup script to delete old log files:

```bash
python "${CLAUDE_PLUGIN_ROOT}/hooks/cleanup_logs.py" --days ${1:-30} ${2:---verbose}
```

If the user specified `--dry-run`, add that flag. Otherwise run with `--verbose` to show progress.

## What Gets Deleted

- All `.jsonl` files in `.claude/logs/hooks/` older than the specified days
- Both base files (`events-2025-12-05.jsonl`) and rotated files (`events-2025-12-05-001.jsonl`)

## Configuration

The default retention period can be configured via environment variable:

```bash
# In .claude/settings.json "env" section:
"CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS": "30"
```

## Safety Notes

- Use `--dry-run` first to preview what will be deleted
- Deleted files cannot be recovered
- Log files contain session metadata for debugging - ensure you don't need them before deleting
