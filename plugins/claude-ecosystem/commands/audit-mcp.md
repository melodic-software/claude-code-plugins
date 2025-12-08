---
description: Audit MCP server configurations for quality, compliance, and security
argument-hint: [project | user | settings | all] [--force] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(test:*), Glob, Task, Skill
---

# Audit MCP Command

You are tasked with auditing MCP server configurations for quality, compliance, and security.

## Step 0: Load Official Documentation (REQUIRED)

**CRITICAL**: Before discovering MCP configurations, invoke the `docs-management` skill to get authoritative information about MCP configuration locations:

```text
Invoke docs-management skill with keywords: "MCP installation scopes", ".mcp.json", "mcpServers"
```

This ensures the audit uses current official documentation for configuration discovery.

## What Gets Audited

This command audits MCP server configurations from multiple sources:

- **Project scope**: `.mcp.json` in project root (version-controlled, team-shared)
- **User settings**: `~/.claude/settings.json` with `mcpServers` key (CLI-configured servers)
- **User/Local scope**: `~/.claude.json` with `mcpServers` key (per official docs)
- **Plugin scope**: `.mcp.json` files within plugin directories
- **Enterprise scope**: `managed-mcp.json` in system directories

For each configuration, the audit validates:

- JSON structure and syntax
- Server configuration fields
- Transport types (stdio, HTTP, SSE)
- Authentication patterns
- Environment variable usage
- Security (no exposed credentials)

## Command Arguments

This command accepts **scope selectors and/or flags** as arguments:

- **No arguments**: Audit all discoverable MCP configurations
- **project**: Audit only `.mcp.json` in project root
- **user**: Audit user-level configs (`~/.claude/settings.json` and `~/.claude.json`)
- **settings**: Audit only `~/.claude/settings.json` mcpServers
- **all**: Audit all MCP configs (project + user + settings + plugins)
- **--force**: Audit regardless of modification status

**Argument format**:

- Scope first (e.g., `project`, `user`, `settings`, `all`)
- Flags last: `--force` (case-insensitive)

## Step 1: Get Current Date (REQUIRED)

```bash
date -u +"%Y-%m-%d"
```

## Step 2: Discover MCP Configurations

### Detection Algorithm

Check all official MCP configuration locations:

```bash
# 1. Check for project-scoped .mcp.json (version-controlled)
if [ -f ".mcp.json" ]; then
    echo "HAS_PROJECT_MCP=true"
    echo "PROJECT_MCP_PATH=.mcp.json"
fi

# 2. Check user settings.json for mcpServers (CLI-configured servers)
if [ -f "$HOME/.claude/settings.json" ]; then
    # Check if mcpServers key exists
    if grep -q '"mcpServers"' "$HOME/.claude/settings.json" 2>/dev/null; then
        echo "HAS_SETTINGS_MCP=true"
        echo "SETTINGS_MCP_PATH=$HOME/.claude/settings.json"
    fi
fi

# 3. Check ~/.claude.json for mcpServers (per official docs)
if [ -f "$HOME/.claude.json" ]; then
    if grep -q '"mcpServers"' "$HOME/.claude.json" 2>/dev/null; then
        echo "HAS_USER_MCP=true"
        echo "USER_MCP_PATH=$HOME/.claude.json"
    fi
fi

# 4. Check for plugin MCP configs (in marketplace repos)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    find plugins -name ".mcp.json" 2>/dev/null | while read -r f; do
        echo "PLUGIN_MCP_PATH=$f"
    done
fi

# 5. Check for enterprise managed-mcp.json (platform-specific)
# macOS: /Library/Application Support/ClaudeCode/managed-mcp.json
# Linux: /etc/claude-code/managed-mcp.json
# Windows: %ProgramData%\ClaudeCode\managed-mcp.json
```

### Build MCP Config List

```text
mcp_configs = []

# Project scope - .mcp.json in repo root
if scope in ["project", "all", None]:
  if exists(".mcp.json"):
    mcp_configs.append({
      scope: "project",
      path: ".mcp.json",
      type: "standalone",  # Full .mcp.json file
      audit_log: ".mcp-audit-log.md"
    })

# User settings - ~/.claude/settings.json (most common for CLI users)
if scope in ["user", "settings", "all", None]:
  if exists("~/.claude/settings.json") and has_mcpServers_key:
    mcp_configs.append({
      scope: "settings",
      path: "~/.claude/settings.json",
      type: "embedded",  # mcpServers key within settings
      key: "mcpServers",
      audit_log: "~/.claude/.mcp-settings-audit-log.md"
    })

# User/Local scope - ~/.claude.json (per official docs)
if scope in ["user", "all"]:
  if exists("~/.claude.json") and has_mcpServers_key:
    mcp_configs.append({
      scope: "user",
      path: "~/.claude.json",
      type: "embedded",  # mcpServers key within config
      key: "mcpServers",
      audit_log: "~/.claude/.mcp-user-audit-log.md"
    })

# Plugin scope - .mcp.json within plugins
if scope == "all":
  for each plugin with .mcp.json:
    mcp_configs.append({
      scope: "plugin:{name}",
      path: "{plugin}/.mcp.json",
      type: "standalone"
    })
```

### Apply Scope Filter

Based on arguments, filter to requested scope(s).

## Step 3: Parse Arguments

1. Parse scope selector from arguments
2. Parse flags (--force)
3. Build filtered MCP config list

## Step 4: Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**MCP configurations discovered**: X

### Files to Audit:
1. [settings] ~/.claude/settings.json (mcpServers) - X servers configured
2. [project] .mcp.json - Y servers configured
3. [user] ~/.claude.json (mcpServers) - Z servers configured
...

Proceeding with audit...
```

## Step 5: Execute Audits

### For Each MCP Configuration

1. **Invoke mcp-auditor subagent**:

   ```text
   Use the mcp-auditor subagent to audit the MCP configuration.

   Context:
   - Scope: {project/settings/user/plugin}
   - File path: {full path}
   - Config type: {standalone .mcp.json | embedded mcpServers key}
   - Last audit: {date} or "Never audited"

   The subagent auto-loads mcp-integration skill and handles the audit.
   ```

2. Wait for completion
3. Update audit log (if applicable)
4. Report results

### Parallel Execution

If multiple MCP configs, audit in parallel (one subagent per file).

## Step 6: Final Summary

```markdown
## MCP Audit Complete

**Total audited**: X MCP configurations
**Total servers**: Y servers across all configs
**By scope**:
- Settings: 1 file (N servers)
- Project: 1 file (M servers)
- User: 1 file (P servers)
- Plugin: Q files

**Results**:
- Passed: Y files
- Passed with warnings: Z files
- Failed: W files

### Details

| Scope | File | Servers | Result | Score |
| ------- | ------ | --------- | -------- | ------- |
| settings | ~/.claude/settings.json | 5 | PASS | 95/100 |
| project | .mcp.json | 2 | PASS WITH WARNINGS | 78/100 |

**Security Alerts**:
- [List any security issues found - exposed credentials, etc.]

**Server Configuration Issues**:
- [List any server configuration problems]

**Next Steps**:
- Address any security warnings immediately
- Fix invalid server configurations
- Re-audit after changes
```

## Important Notes

### Configuration Location Summary

Per official Claude Code documentation:

| Scope | Location | Format | Shared |
| ------- | ---------- | -------- | -------- |
| Project | `.mcp.json` in repo root | Standalone file | Yes (version control) |
| Settings | `~/.claude/settings.json` | `mcpServers` key | No (personal) |
| User/Local | `~/.claude.json` | `mcpServers` key | No (personal) |
| Plugin | `{plugin}/.mcp.json` | Standalone file | Via plugin |
| Enterprise | `managed-mcp.json` | Standalone file | Org-managed |

### Security Considerations

**Critical:** MCP configurations should NEVER contain:

- Hardcoded API keys or tokens (use env var expansion like `${API_KEY}`)
- Passwords or credentials
- Private server endpoints without authentication

If found, mark as **CRITICAL FAILURE** and alert user.

### Transport Types

Valid transport types:

- `stdio`: Standard input/output (local processes)
- `http`: HTTP transport (recommended for remote servers)
- `sse`: Server-Sent Events (deprecated, use HTTP)

Verify each server uses a valid transport type.

### Environment Variable Expansion

MCP configs support environment variable expansion. Verify:

- Env vars are used for sensitive values: `${VAR}` or `${VAR:-default}`
- Expansion syntax is correct
- Referenced env vars are documented or likely to exist

### Windows Considerations

- Windows requires `cmd /c` wrapper for npx-based stdio servers
- Paths use forward slashes in JSON configs
- User config at `%USERPROFILE%\.claude\settings.json`

### Cross-Platform Paths

- Project MCP: `.mcp.json` in project root
- User settings: `~/.claude/settings.json` (or `%USERPROFILE%\.claude\settings.json`)
- User config: `~/.claude.json` (or `%USERPROFILE%\.claude.json`)
