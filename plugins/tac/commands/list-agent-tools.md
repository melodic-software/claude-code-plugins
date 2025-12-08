---
description: List available tools for custom agent configuration
---

# List Agent Tools

List available tools for custom agent configuration.

## Instructions

Display the default Claude Code tools and guidance for tool access configuration.

## Output

```markdown
## Claude Code Default Tools

### File Operations

| Tool | Purpose | Common Use |
| ------ | --------- | ------------ |
| `Read` | Read file contents | Codebase exploration |
| `Write` | Write new files | File creation |
| `Edit` | Edit existing files | Code modification |
| `MultiEdit` | Multiple edits at once | Batch changes |
| `Glob` | Find files by pattern | File discovery |
| `Grep` | Search file contents | Code search |

### Execution

| Tool | Purpose | Common Use |
| ------ | --------- | ------------ |
| `Bash` | Execute shell commands | Build, test, deploy |
| `BashOutput` | Get command output | Command results |

### Web

| Tool | Purpose | Common Use |
| ------ | --------- | ------------ |
| `WebFetch` | Fetch web content | Documentation |
| `WebSearch` | Search the web | Research |

### Agent

| Tool | Purpose | Common Use |
| ------ | --------- | ------------ |
| `Task` | Spawn subagents | Parallel work |
| `TodoWrite` | Track tasks | Progress tracking |

---

## Tool Access Configuration

### Whitelist (allowed_tools)

Use when agent needs only specific tools:

```python
allowed_tools=["Read", "Write", "Bash"]
```

### Blacklist (disallowed_tools)

Use when agent needs most tools except some:

```python
disallowed_tools=["WebFetch", "WebSearch", "Task"]
```

### Disable All Default Tools

For agents with only custom tools:

```python
disallowed_tools=["*"]
```

### Custom Tools

Add via MCP server:

```python
mcp_servers={"my_server": my_mcp_server}
allowed_tools=["mcp__my_server__my_tool"]
```

Tool naming: `mcp__<server>__<tool>`

---

## Tool Access Patterns

### Minimal Agent

For focused, single-purpose agents:

```python
allowed_tools=["Read"]  # Read-only exploration
```

### Code Agent

For agents that modify code:

```python
allowed_tools=["Read", "Write", "Edit", "Glob", "Grep", "Bash"]
```

### Research Agent

For agents that gather information:

```python
allowed_tools=["Read", "Glob", "Grep", "WebFetch", "WebSearch"]
```

### Pure Custom Tools

For agents with only custom functionality:

```python
mcp_servers={"domain": domain_server}
allowed_tools=["mcp__domain__tool1", "mcp__domain__tool2"]
disallowed_tools=["*"]
```

### Parallel Agent

For agents that spawn subagents:

```python
allowed_tools=["Task", "Read", "Glob", "Grep"]
```

---

## Token Overhead Warning

> "15 extra tools consume space in your agent's mind."

Each tool definition consumes context window space even if never used. Strip unnecessary tools for:

- Better context utilization
- Reduced confusion
- Clearer agent focus

---

## Related Commands

- `/create-agent` - Scaffold new custom agent
- `/create-tool` - Generate custom tool boilerplate

## Related Skills

- @custom-agent-design - Agent design workflow
- @tool-design - Tool creation workflow

## Related Memory

- @core-four-custom.md - Tools in Core Four
- @custom-tool-patterns.md - Tool patterns

```text

## Notes

- Use /context command to understand tool overhead
- Strip tools your agent doesn't need
- Custom tools require ClaudeSDKClient (not query())
