# MCP Credential Management Patterns

This document describes recommended approaches for managing API keys and credentials when configuring MCP servers in Claude Code.

## Recommended Approaches (by preference)

### 1. OAuth 2.0 (Best - when supported)

```bash
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp
/mcp  # Authenticate via OAuth
```

**Benefits:**

- Tokens stored in system keychain (macOS) or secure storage
- Automatic refresh
- No manual credential handling

**Limitation:** Only available for MCP servers that support OAuth 2.0.

### 2. Environment Variables + ${VAR} Expansion (Good)

Set credentials in your shell profile, then reference them in config files.

**Step 1: Set environment variables**

Windows PowerShell (persistent, User scope):

```powershell
[Environment]::SetEnvironmentVariable("PERPLEXITY_API_KEY", "your-key", "User")
[Environment]::SetEnvironmentVariable("FIRECRAWL_API_KEY", "your-key", "User")
# Restart terminal for changes to take effect
```

macOS/Linux (add to ~/.bashrc or ~/.zshrc):

```bash
export PERPLEXITY_API_KEY="your-key"
export FIRECRAWL_API_KEY="your-key"
```

**Step 2: Reference in config using ${VAR} expansion**

In `.mcp.json` (project-level, can be version controlled):

```json
{
  "mcpServers": {
    "perplexity": {
      "command": "npx",
      "args": ["-y", "perplexity-mcp"],
      "env": {
        "PERPLEXITY_API_KEY": "${PERPLEXITY_API_KEY}"
      }
    }
  }
}
```

Or in `~/.claude/settings.json` (user-level):

```json
{
  "mcpServers": {
    "perplexity": {
      "command": "npx",
      "args": ["-y", "perplexity-mcp"],
      "env": {
        "PERPLEXITY_API_KEY": "${PERPLEXITY_API_KEY}"
      }
    }
  }
}
```

**Benefits:**

- Keys stored in env vars (not committed to version control)
- Config files can be shared/committed (they only contain variable references)
- Works across all projects if env var is set globally

**Note:** Variable expansion (`${VAR}`) works in:

- `mcpServers.*.env` values
- `mcpServers.*.url` (for HTTP servers)
- `mcpServers.*.headers` values
- `mcpServers.*.command` and `mcpServers.*.args`

### 3. Hardcoded in User Settings (Acceptable)

```json
// ~/.claude/settings.json - NOT version controlled
{
  "mcpServers": {
    "perplexity": {
      "command": "npx",
      "args": ["-y", "perplexity-mcp"],
      "env": {
        "PERPLEXITY_API_KEY": "pplx-actual-key-here"
      }
    }
  }
}
```

**When this is acceptable:**

- Personal development machines
- Keys not shared with anyone
- Convenience outweighs security concern

**Audit result:** WARNING (not failure)

- Keys are NOT exposed via version control
- Flagged as warning in `/claude-ecosystem:audit-settings`
- Acceptable risk for personal use

### 4. Hardcoded in Project Settings (NOT Recommended)

```json
// .claude/settings.json - VERSION CONTROLLED!
{
  "mcpServers": {
    "example": {
      "env": {
        "API_KEY": "actual-key-here"  // DO NOT DO THIS
      }
    }
  }
}
```

**Why this is bad:**

- Keys committed to git history
- Anyone who clones the repo gets your keys
- Keys remain in history even after removal
- Requires git history cleanup to fully remove

**Audit result:** CRITICAL FAILURE

## Summary Table

| Approach | Security | Convenience | Audit Result |
|----------|----------|-------------|--------------|
| OAuth 2.0 | Excellent | Good | PASS |
| Env vars + ${VAR} | Good | Good | PASS |
| Hardcoded in user settings | Acceptable | Excellent | WARNING |
| Hardcoded in project settings | Bad | - | CRITICAL FAIL |

## Related Documentation

- Official MCP documentation: Use `docs-management` skill with query "mcp server configuration"
- Settings audit: `/claude-ecosystem:audit-settings`
- Environment variable expansion: Official Claude Code docs on `.mcp.json`

---

**Last Updated:** 2025-12-06
