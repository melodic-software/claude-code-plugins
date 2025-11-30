# inject-current-date Hook

Automatically injects the current UTC date and time into Claude's context at session start.

## Purpose

This hook eliminates the need for Claude to manually run `date` commands at session start. The current UTC timestamp is automatically injected into context, ensuring Claude always has accurate temporal awareness.

## How It Works

1. **Event**: Triggers on `SessionStart` (when Claude Code starts a new session)
2. **Action**: Injects current UTC date/time as `additionalContext`
3. **Format**: Provides both human-readable UTC and ISO 8601 formats

## Injected Context

```text
<session-context>
CURRENT DATE/TIME (automatically injected at session start):
- UTC: 2025-11-28 00:15:45 UTC
- ISO 8601: 2025-11-28T00:15:45Z

This timestamp is accurate as of session start. For time-sensitive operations requiring the latest time, execute a date command directly.
</session-context>
```

## Benefits

- **Token savings**: Removes ~100 tokens of date instruction from CLAUDE.md
- **Reliability**: Date is always injected automatically - no reliance on LLM remembering to check
- **Accuracy**: Uses system time, not LLM assumptions

## Configuration

Edit `config.yaml` to disable:

```yaml
enabled: false
```

## Dependencies

- `jq` - For JSON output formatting (typically pre-installed)

## Related

- Replaces the CLAUDE.md instruction: "ALWAYS get the current date"
- See `.claude/hooks/README.md` for hook architecture overview
