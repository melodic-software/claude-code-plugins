---
description: Audit Claude Code settings.json files for quality, compliance, and security
argument-hint: [project | user | all] [--force] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(test:*), Glob, Task, Skill
---

# Audit Settings Command

You are tasked with auditing Claude Code settings.json files for quality, compliance, and security.

## What Gets Audited

This command audits:

- JSON syntax validity
- Schema compliance (valid settings options)
- Permission rules configuration
- Sandbox settings
- Environment variable configuration
- Security (no exposed secrets)

## Command Arguments

This command accepts **scope selectors and/or flags** as arguments:

- **No arguments**: Audit all discoverable settings files
- **project**: Audit only `.claude/settings.json`
- **user**: Audit only `~/.claude/settings.json`
- **all**: Audit all settings (project + user + any plugin settings)
- **--force**: Audit regardless of modification status

**Argument format**:

- Scope first (e.g., `project`, `user`, `all`)
- Flags last: `--force` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

```bash
date -u +"%Y-%m-%d"
```

## Step 1: Discover Settings Files

### Detection Algorithm

```bash
# Check for project settings
if [ -f ".claude/settings.json" ]; then
    echo "HAS_PROJECT_SETTINGS=true"
fi

# Check for user settings
if [ -f "$HOME/.claude/settings.json" ]; then
    echo "HAS_USER_SETTINGS=true"
fi

# Check for plugin settings (in marketplace repos)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Find all .claude/settings.json within plugin directories
    find plugins -name "settings.json" -path "*/.claude/*"
fi
```

### Build Settings List

```text
settings_files = []

if scope == "project" or scope == "all" or no_scope:
  if exists(".claude/settings.json"):
    settings_files.append({
      scope: "project",
      path: ".claude/settings.json",
      audit_log: ".claude/.settings-audit-log.md"
    })

if scope == "user" or scope == "all":
  if exists("~/.claude/settings.json"):
    settings_files.append({
      scope: "user",
      path: "~/.claude/settings.json",
      audit_log: "~/.claude/.settings-audit-log.md"
    })

if scope == "all":
  # Include plugin-embedded settings if any
  for each plugin with .claude/settings.json:
    settings_files.append({
      scope: "plugin:{name}",
      path: "{plugin}/.claude/settings.json"
    })
```

### Apply Scope Filter

Based on arguments, filter to requested scope(s).

## Step 2: Parse Arguments

1. Parse scope selector from arguments
2. Parse flags (--force)
3. Build filtered settings list

## Step 3: Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**Settings files discovered**: X

### Files to Audit:
1. [project] .claude/settings.json (last modified: YYYY-MM-DD)
2. [user] ~/.claude/settings.json (last modified: YYYY-MM-DD)
...

Proceeding with audit...
```

## Step 4: Execute Audits

### For Each Settings File

1. **Invoke settings-auditor subagent**:

   ```text
   Use the settings-auditor subagent to audit the settings file.

   Context:
   - Scope: {project/user/plugin}
   - File path: {full path}
   - Last audit: {date} or "Never audited"

   The subagent auto-loads settings-management skill and handles the audit.
   ```

2. Wait for completion
3. Update audit log (if applicable)
4. Report results

### Parallel Execution

If multiple settings files, audit in parallel (one subagent per file).

## Step 5: Final Summary

```markdown
## Settings Audit Complete

**Total audited**: X settings files
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
| project | .claude/settings.json | PASS | 95/100 |
| user | ~/.claude/settings.json | PASS WITH WARNINGS | 78/100 |

**Security Alerts**:
- [List any security issues found]

**Next Steps**:
- Address any security warnings immediately
- Review and fix schema compliance issues
- Re-audit after changes
```

## Important Notes

### Security Considerations

**Critical:** Settings files should NEVER contain:

- API keys or tokens
- Passwords
- Private credentials

If found, mark as **CRITICAL FAILURE** and alert user.

### Precedence Hierarchy

Settings are applied in order (lower overrides higher):

1. Enterprise/managed settings (highest)
2. Local/project settings
3. User settings (lowest)

When auditing, consider how settings interact across levels.

### Cross-Platform Paths

- User settings: `~/.claude/settings.json` on all platforms
- Project settings: `.claude/settings.json` relative to project root
- Use forward slashes in paths
