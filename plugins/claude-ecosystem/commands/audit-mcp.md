---
description: Audit MCP server configurations for quality, compliance, and security
argument-hint: [project | user | all] [--force] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(test:*), Glob, Task, Skill
---

# Audit MCP Command

You are tasked with auditing MCP server configurations for quality, compliance, and security.

## What Gets Audited

This command audits:

- `.mcp.json` structure and syntax
- Server configuration fields
- Transport types (stdio, HTTP, SSE)
- Authentication patterns
- Environment variable usage
- Scope appropriateness (project, user, plugin)

## Command Arguments

This command accepts **scope selectors and/or flags** as arguments:

- **No arguments**: Audit all discoverable MCP configurations
- **project**: Audit only `.mcp.json` in project root
- **user**: Audit only `~/.claude/.mcp.json`
- **all**: Audit all MCP configs (project + user + any plugin configs)
- **--force**: Audit regardless of modification status

**Argument format**:

- Scope first (e.g., `project`, `user`, `all`)
- Flags last: `--force` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

```bash
date -u +"%Y-%m-%d"
```

## Step 1: Discover MCP Configurations

### Detection Algorithm

```bash
# Check for project MCP config
if [ -f ".mcp.json" ]; then
    echo "HAS_PROJECT_MCP=true"
fi

# Check for user MCP config
if [ -f "$HOME/.claude/.mcp.json" ]; then
    echo "HAS_USER_MCP=true"
fi

# Check for plugin MCP configs (in marketplace repos)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Find all .mcp.json within plugin directories
    find plugins -name ".mcp.json" 2>/dev/null
fi
```

### Build MCP Config List

```text
mcp_files = []

if scope == "project" or scope == "all" or no_scope:
  if exists(".mcp.json"):
    mcp_files.append({
      scope: "project",
      path: ".mcp.json",
      audit_log: ".mcp-audit-log.md"
    })

if scope == "user" or scope == "all":
  if exists("~/.claude/.mcp.json"):
    mcp_files.append({
      scope: "user",
      path: "~/.claude/.mcp.json",
      audit_log: "~/.claude/.mcp-audit-log.md"
    })

if scope == "all":
  # Include plugin-embedded MCP configs if any
  for each plugin with .mcp.json:
    mcp_files.append({
      scope: "plugin:{name}",
      path: "{plugin}/.mcp.json"
    })
```

### Apply Scope Filter

Based on arguments, filter to requested scope(s).

## Step 2: Parse Arguments

1. Parse scope selector from arguments
2. Parse flags (--force)
3. Build filtered MCP config list

## Step 3: Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**MCP configurations discovered**: X

### Files to Audit:
1. [project] .mcp.json (last modified: YYYY-MM-DD)
2. [user] ~/.claude/.mcp.json (last modified: YYYY-MM-DD)
...

Proceeding with audit...
```

## Step 4: Execute Audits

### For Each MCP Configuration

1. **Invoke mcp-auditor subagent**:

   ```text
   Use the mcp-auditor subagent to audit the MCP configuration.

   Context:
   - Scope: {project/user/plugin}
   - File path: {full path}
   - Last audit: {date} or "Never audited"

   The subagent auto-loads mcp-integration skill and handles the audit.
   ```

2. Wait for completion
3. Update audit log (if applicable)
4. Report results

### Parallel Execution

If multiple MCP configs, audit in parallel (one subagent per file).

## Step 5: Final Summary

```markdown
## MCP Audit Complete

**Total audited**: X MCP configurations
**By scope**:
- Project: 1 file
- User: 1 file
- Plugin: N files

**Results**:
- Passed: Y files
- Passed with warnings: Z files
- Failed: W files

### Details

| Scope | File | Result | Score |
|-------|------|--------|-------|
| project | .mcp.json | PASS | 95/100 |
| user | ~/.claude/.mcp.json | PASS WITH WARNINGS | 78/100 |

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

### Security Considerations

**Critical:** MCP configurations should NEVER contain:

- Hardcoded API keys or tokens (use env var expansion)
- Passwords or credentials
- Private server endpoints without authentication

If found, mark as **CRITICAL FAILURE** and alert user.

### Transport Types

Valid transport types:

- `stdio`: Standard input/output
- `http`: HTTP transport (supports authentication headers)
- `sse`: Server-Sent Events

Verify each server uses a valid transport type.

### Environment Variable Expansion

MCP configs support environment variable expansion. Verify:

- Env vars are used for sensitive values
- Expansion syntax is correct
- Referenced env vars are likely to exist

### Cross-Platform Paths

- User MCP config: `~/.claude/.mcp.json`
- Project MCP config: `.mcp.json` in project root
- Use forward slashes in paths
