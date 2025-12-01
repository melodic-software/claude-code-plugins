# Session Configuration

This document covers Claude Code session management, debugging configuration, and operational patterns for advanced usage.

## Debugging with HTTPS_PROXY

Configure a proxy to inspect raw traffic between Claude Code and the API.

### Setup

Set environment variables before starting Claude Code:

```bash
export HTTPS_PROXY="http://localhost:8080"
export HTTP_PROXY="http://localhost:8080"
```

Or in settings.json:

```json
{
  "env": {
    "HTTPS_PROXY": "http://localhost:8080",
    "HTTP_PROXY": "http://localhost:8080"
  }
}
```

### Use Cases

- **Inspect prompts**: See exactly what prompts Claude Code sends to the API
- **Debug tool calls**: Examine tool call payloads and responses
- **Network sandboxing**: Fine-grained control over network access for background agents
- **Audit logging**: Capture all API traffic for compliance or debugging

### Security Considerations

- Only use trusted proxies - all API traffic (including credentials) passes through
- Disable proxy configuration after debugging
- Never commit proxy settings to version control
- Use localhost proxies for development; avoid remote proxies for sensitive work

## Timeout Configuration

Adjust timeouts for long-running operations.

### Available Settings

| Setting                | Default        | Description                        |
| ---------------------- | -------------- | ---------------------------------- |
| `BASH_MAX_TIMEOUT_MS`  | 120000 (2 min) | Maximum timeout for bash commands  |
| `MCP_TOOL_TIMEOUT`     | 60000 (1 min)  | Timeout for MCP tool operations    |

### When to Adjust

**Increase timeouts when:**

- Running complex builds or test suites
- Processing large datasets
- Executing long-running scripts
- Working with slow external services

**Keep defaults when:**

- Normal development work
- Using background tasks (preferred for long operations)
- Quick validation checks

### Configuration

In settings.json:

```json
{
  "env": {
    "BASH_MAX_TIMEOUT_MS": "300000",
    "MCP_TOOL_TIMEOUT": "120000"
  }
}
```

Or via environment:

```bash
export BASH_MAX_TIMEOUT_MS=300000
export MCP_TOOL_TIMEOUT=120000
```

**Note:** For very long operations, prefer using background tasks (`run_in_background` parameter) over increasing timeouts.

## API Key Management

### Direct Configuration

Set API key via environment variable:

```bash
export ANTHROPIC_API_KEY="your-api-key"
```

### apiKeyHelper Pattern

For dynamic key injection (enterprise environments, key rotation):

```json
{
  "apiKeyHelper": "/path/to/your/key-helper-script"
}
```

The helper script should output the API key to stdout. This enables:

- **Key rotation**: Script can fetch fresh keys from vault/secrets manager
- **Environment-specific keys**: Different keys for dev/staging/prod
- **Audit logging**: Track key usage patterns
- **Credential isolation**: Keys never stored in plain config files

### Enterprise vs Per-Seat Licensing

| Model           | Description         | Best For                           |
| --------------- | ------------------- | ---------------------------------- |
| Per-seat        | Fixed cost per user | Predictable budgets, uniform usage |
| Usage-based API | Pay per token       | Variable usage, high-volume teams  |

**Usage-based benefits:**

- Accounts for 1:100x variance in developer usage patterns
- Engineers can experiment with non-Claude-Code LLM scripts under same account
- Better cost attribution and tracking

## Session Management

### Session Persistence

Claude Code stores session history in:

- **macOS/Linux**: `~/.claude/projects/`
- **Windows**: `%USERPROFILE%\.claude\projects\`

Each project gets a subdirectory with conversation logs.

### Resume Commands

**`claude --resume`**: Resume a previous session

- Restores full conversation context
- Useful for picking up where you left off
- Can resume sessions from days ago

**`claude --continue`**: Continue after terminal issues

- Reconnects to most recent session
- Handles terminal crashes/disconnections
- Less context restoration than --resume

### When to Use Each

| Situation                      | Command              |
| ------------------------------ | -------------------- |
| Terminal crashed               | `claude --continue`  |
| Return to old work             | `claude --resume`    |
| Start fresh                    | `claude` (no flags)  |
| Quick question in same project | `claude --continue`  |

## Log Analysis Patterns

### Location

Session logs are stored in `~/.claude/projects/<project-hash>/`.

### Common Error Pattern Mining

Use meta-analysis to improve CLAUDE.md and internal tooling:

```bash
# Find common errors across sessions
grep -r "error\|Error\|ERROR" ~/.claude/projects/ | sort | uniq -c | sort -rn

# Find common permission requests
grep -r "permission" ~/.claude/projects/ | head -50

# Analyze tool usage patterns
grep -r "tool_use" ~/.claude/projects/ | jq '.name' | sort | uniq -c
```

### Data-Driven Improvement Flywheel

1. **Collect**: Gather error patterns from session logs
2. **Analyze**: Identify common failure modes
3. **Fix**: Update CLAUDE.md, tooling, or workflows
4. **Verify**: Check if errors decrease in subsequent sessions

Example workflow:

```bash
# Query logs for what Claude gets stuck on
query-claude-logs --since 7d | claude -p "analyze common mistakes and suggest CLAUDE.md improvements"
```

## Session Restart Workflows

### Simple Restart: /clear + /catchup

Best for: Routine context refresh during normal work

1. `/clear` - Complete context reset
2. `/catchup` (custom command) - Re-read changed files in current git branch

This gives a clean slate with targeted context reload.

### Document & Clear (Complex Tasks)

Best for: Multi-session complex work spanning hours or days

1. Have Claude dump plan and progress to a .md file:

   ```text
   Write your current plan, progress, and key context to .claude/temp/progress-feature-x.md
   ```

2. `/clear` the context
3. Start new session:

   ```text
   Read .claude/temp/progress-feature-x.md and continue from where we left off
   ```

**Why this works:**

- External memory survives context boundaries
- No loss of critical decisions or architectural choices
- Enables truly long-running tasks
- Progress file can be version-controlled if needed

### Decision Tree

```text
Need to reset context?
|-- Simple task complete -> /clear
|-- Mid-task, context bloated -> /compact (reluctantly)
|-- Complex multi-day work -> Document & Clear
|-- Terminal crashed -> claude --continue
+-- Resume old session -> claude --resume
```

## Why /compact is Risky

The `/compact` command compresses context, but has risks:

**Problems:**

- Opaque compression algorithm - you don't control what's preserved
- Valuable context may be silently destroyed
- Not well-optimized for all use cases
- Can lose critical architectural decisions or context

**Prefer alternatives:**

- `/clear` + `/catchup` for clean reset with targeted reload
- Document & Clear for complex tasks
- Structured note-taking (`.claude/temp/` files) for persistence

**When /compact might be acceptable:**

- Mid-task, no good stopping point
- Simple task, low risk of context loss
- Context window nearly full but need to finish one more step

## Self-Audit: Allowed Permissions

Periodically review what commands Claude can auto-run:

```bash
# View current permissions
cat ~/.claude/settings.json | jq '.permissions'

# Or in Claude Code
/permissions
```

**Audit questions:**

- Are all allowed tools still needed?
- Any overly broad patterns that should be restricted?
- Any denied patterns that are too restrictive?

---

**Last Updated:** 2025-11-30
