---
description: Audit Claude Code plugins for quality, compliance, and distribution readiness
argument-hint: [plugin-name-1] [plugin-name-2] ... [--force] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(grep:*), Bash(test:*), Glob, Task, Skill
---

# Audit Plugins Command

You are tasked with auditing Claude Code plugins for quality, compliance, and distribution readiness.

## What Gets Audited

This command audits:

- plugin.json manifest structure and validity
- Required fields (name, description, version)
- Component organization (commands, skills, agents, hooks)
- Namespace compliance and consistency
- Documentation completeness
- Distribution and marketplace readiness

## Command Arguments

This command accepts **plugin names and/or flags** as arguments:

- **No arguments**: Audit only plugins that need it (modified since last audit, never audited, or >90 days old)
- **--force**: Audit ALL plugins regardless of modification/audit status
- **One plugin name**: Audit a single plugin directly
- **Multiple plugin names**: Audit specified plugins in parallel batches

## Step 0: Get Current Date (REQUIRED)

```bash
date -u +"%Y-%m-%d"
```

## Step 1: Discover Plugin Sources

### Detection Algorithm

```bash
# Check for marketplace (indicates multi-plugin repo)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Marketplace repo - discover all plugins
    echo "REPO_TYPE=marketplace"
fi

# Check for single plugin repo
if [ -f ".claude-plugin/plugin.json" ]; then
    echo "REPO_TYPE=plugin"
fi
```

### Build Plugin List

**For marketplace repos:**

```text
For each directory with .claude-plugin/plugin.json OR plugin.json:
  plugins.append({
    name: {plugin-name from manifest},
    path: "{plugin-dir}/",
    manifest: "{plugin-dir}/.claude-plugin/plugin.json" or "{plugin-dir}/plugin.json",
    audit_log: "{plugin-dir}/.audit-log.md"
  })
```

**For single plugin repos:**

```text
plugins.append({
  name: {plugin-name from manifest},
  path: "./",
  manifest: ".claude-plugin/plugin.json",
  audit_log: "./.audit-log.md"
})
```

## Step 2: Parse Arguments and Read Context

1. Parse flags from arguments
2. Read audit logs for each discovered plugin
3. Build prioritized audit queue

## Step 3: Smart Prioritization

Use standard prioritization algorithm (modified > never audited > stale > unchanged).

### Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**Plugins discovered**: X
**Will audit**: Y

### Audit Queue (priority order):
1. plugin-name-1 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
...

Proceeding with audit...
```

## Step 4: Execute Audits

### Single Plugin (One Argument)

1. **Invoke plugin-auditor subagent**:

   ```text
   Use the plugin-auditor subagent to audit the "{plugin-name}" plugin.

   Context:
   - Plugin path: {full path}
   - Manifest location: {path to plugin.json}
   - Last audit: {date} or "Never audited"

   The subagent auto-loads plugin-development skill and handles the audit.
   ```

2. Wait for completion
3. Update audit log
4. Report results

### Multiple Plugins

Use standard batching strategy (3-5 per batch) with parallel plugin-auditor subagents.

## Step 5: Final Summary

```markdown
## Plugin Audit Complete

**Total audited**: X plugins
**Results**:
- Passed: Y plugins
- Passed with warnings: Z plugins
- Failed: W plugins

### Details

| Plugin | Result | Score |
|--------|--------|-------|
| plugin-name | PASS | 92/100 |

**Next Steps**:
- Review detailed reports
- Address warnings and recommendations
- Re-audit failed plugins after fixes
```

## Important Notes

### Plugin-Specific Considerations

- Plugins may have .claude-plugin/plugin.json OR plugin.json at root
- Check all component directories even if empty
- Verify namespace prefix consistency across all components
- Assess marketplace readiness for distribution

### Error Handling

If plugin.json doesn't exist or is invalid:

- Mark as critical failure
- Continue auditing other plugins
