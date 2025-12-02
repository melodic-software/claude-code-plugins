# Claude Code Observability Plugin

Observability hooks for Claude Code: comprehensive event logging, performance metrics, and session diagnostics.

## Overview

This plugin provides full observability into Claude Code hook execution without modifying behavior. All hooks are purely observational - they log events but never block operations or enforce rules.

**Key Benefits:**

- **Full audit trail** - Track all Claude Code interactions
- **Performance analysis** - Monitor hook execution timing
- **Troubleshooting** - Debug hook behavior and timing issues
- **Optional by design** - Uninstall plugin to completely disable all logging

## Installation

```bash
/plugin install claude-code-observability@claude-code-plugins
```

## Uninstallation

To completely disable all observability hooks (zero overhead):

```bash
/plugin uninstall claude-code-observability
```

## Hooks Provided

### log-hook-events

Comprehensive logging for all 10 Claude Code hook events:

| Event | Description |
| ----- | ----------- |
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

**Log Format:** JSON Lines (JSONL) with daily rotation
**Log Location:** `.claude/hooks/log-hook-events/logs/{event}/YYYY-MM-DD.jsonl`

For detailed documentation, see [hooks/log-hook-events/README.md](hooks/log-hook-events/README.md).

## Configuration

### Disable Without Uninstalling

If you want to keep the plugin installed but temporarily disable logging:

**Disable ALL logging hooks:**

```yaml
# .claude/hooks/log-hook-events/config.yaml
enabled: false
```

**Disable specific events:**

```yaml
# .claude/hooks/log-hook-events/config.yaml
events:
  pretooluse:
    enabled: false  # Disable PreToolUse logging
  posttooluse:
    enabled: true   # Keep PostToolUse logging
```

### Environment Variables

For CI/CD or scripting, you can use environment variables:

```bash
# Disable all hook logging
export CLAUDE_HOOKS_DISABLED=true
```

## Log Storage

Logs are stored in your project's `.claude/hooks/` directory, not within the plugin. This means:

- Logs persist even if plugin is temporarily disabled
- Log location is predictable regardless of plugin installation path
- Existing log analysis scripts continue to work
- Logs are not committed to the plugin repository

## Quick Start: Querying Logs

**View today's PreToolUse events:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/$(date +%Y-%m-%d).jsonl | jq .
```

**Count events by type:**

```bash
cat .claude/hooks/log-hook-events/logs/*/$(date +%Y-%m-%d).jsonl | jq -r '.event' | sort | uniq -c
```

**Find all Write tool uses:**

```bash
cat .claude/hooks/log-hook-events/logs/pretooluse/$(date +%Y-%m-%d).jsonl | jq 'select(.stdin.tool_name == "Write")'
```

**Find slow hook executions (> 100ms):**

```bash
cat .claude/hooks/log-hook-events/logs/*/$(date +%Y-%m-%d).jsonl | jq 'select(.duration_ms > 100)'
```

For more query examples, see [hooks/log-hook-events/README.md](hooks/log-hook-events/README.md).

## Dependencies

- Python 3.8+ (for efficient JSON processing)
- Bash 4.0+
- jq (recommended for log queries)

## Future Observability Features

This plugin is designed to grow with additional observability capabilities:

- **Performance profiling** - Track tool execution times, identify slow operations
- **Token usage tracking** - Log context window usage per session
- **Error aggregation** - Collect and summarize errors across sessions
- **Cost estimation** - Track API call patterns for cost awareness
- **Session analytics** - Summarize session patterns (tools used, duration, outcomes)
- **Diff logging** - Log file changes made during sessions

## Related Plugins

- **claude-ecosystem** - Core Claude Code features (skills, documentation, hooks)
- **code-quality** - Code review, linting, and analysis
- **git** - Git workflow and commit tooling

## License

MIT
