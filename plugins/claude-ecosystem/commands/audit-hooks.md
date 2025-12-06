---
description: Audit Claude Code hooks for quality, compliance, and maintainability
argument-hint: [hook-name-1] [hook-name-2] ... [--force] [--plugin-only] [--project-only] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(grep:*), Bash(test:*), Glob, Task, Skill
---

# Audit Hooks Command

You are tasked with auditing Claude Code hooks for quality, compliance, and maintainability.

## What Gets Audited

This command audits:

- hooks.json configuration structure and validity
- Hook script existence and structure
- Matcher configuration appropriateness
- Environment variable naming conventions
- Decision control usage
- Test existence and coverage

## Command Arguments

This command accepts **hook names and/or flags** as arguments:

- **No arguments**: Audit only hooks that need it (modified since last audit, never audited, or >90 days old)
- **--force**: Audit ALL hooks regardless of modification/audit status
- **--plugin-only**: Only audit plugin hooks (skip local hooks)
- **--project-only**: Only audit project hooks (skip plugin hooks)
- **One hook name**: Audit a single hook directly
- **Multiple hook names**: Audit specified hooks in parallel batches
- **Prefixed names**: `plugin:hook-name` or `local:hook-name` for explicit source targeting

**Argument format**:

- Hook names first (e.g., `prevent-backup-files`, `plugin:markdown-lint`)
- Flags last: `--force`, `--plugin-only`, `--project-only` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

**CRITICAL**: Always get the current UTC date before any operations.

```bash
date -u +"%Y-%m-%d"
```

Store date for use throughout execution: `audit_date = "YYYY-MM-DD"`

## Step 1: Discover Hook Sources

Detect ALL editable hook sources in the current repository:

### Detection Algorithm

```bash
# Check for marketplace (indicates multi-plugin repo)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Marketplace repo - discover all plugins with hooks/
    echo "REPO_TYPE=marketplace"
fi

# Check for single plugin repo
if [ -f ".claude-plugin/plugin.json" ] && [ -d "./hooks" ]; then
    # Plugin repo - hooks in ./hooks/
    echo "REPO_TYPE=plugin"
fi

# Check for local hooks (always check)
if [ -d ".claude/hooks" ] || [ -f ".claude/settings.json" ]; then
    # Has local hooks
    echo "HAS_LOCAL_HOOKS=true"
fi
```

### Build Source List

Based on detection, build list of hook sources:

**For marketplace repos:**

```text
For each plugin directory with .claude-plugin/plugin.json AND hooks/:
  sources.append({
    type: "plugin",
    name: {plugin-name from plugin.json},
    path: "{plugin-dir}/hooks/",
    hooks_json: "{plugin-dir}/hooks/hooks.json",
    audit_log: "{plugin-dir}/hooks/.audit-log.md"
  })
```

**For plugin repos:**

```text
sources.append({
  type: "plugin",
  name: {plugin-name from plugin.json},
  path: "./hooks/",
  hooks_json: "./hooks/hooks.json",
  audit_log: "./hooks/.audit-log.md"
})
```

**For local hooks (always if exists):**

```text
sources.append({
  type: "local",
  name: "local",
  path: ".claude/hooks/",
  hooks_json: ".claude/hooks/hooks.json" or settings.json hooks section,
  audit_log: ".claude/hooks/.audit-log.md"
})
```

### Apply Filters

If `--plugin-only` flag: Filter sources to type="plugin" only
If `--project-only` flag: Filter sources to type="project" only

## Step 2: Parse Arguments and Read Context

1. **Parse flags** from arguments
2. **Read audit logs** for each discovered source
3. **Get all hooks** from each source's hooks.json

## Step 3: Smart Prioritization

When **smart mode** (no hook arguments) or **force mode** (`--force`), calculate audit priority using the same algorithm as other audit commands (see audit-skills for reference).

### Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**Sources discovered**:
- Plugin: {plugin-name} ({N} hooks in {path})
- Local: ({N} hooks in .claude/hooks/)

**Total hooks**: X
**Will audit**: Y

### Audit Queue (priority order):
1. [{source}] hook-name-1 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
...

Proceeding with audit...
```

## Step 4: Execute Audits

### Single Hook (One Argument)

1. **Invoke hook-auditor subagent**:

   ```text
   Use the hook-auditor subagent to audit the "{hook-name}" hook.

   Context:
   - Source: {plugin:{name} or local}
   - Hook path: {full path to hook directory}
   - hooks.json location: {path}
   - Last audit: {date} or "Never audited"

   The subagent auto-loads hook-management skill and handles the audit.
   ```

2. **Wait for completion**
3. **Update source's audit log**
4. **Report results**

### Multiple Hooks (2+ Arguments or Batched Queue)

Use standard batching strategy (3-5 per batch) with parallel hook-auditor subagents.

**For parallel audits:**

- Agents write findings to `.claude/temp/audit-{source}-{hook-name}-latest.md`
- Main thread collects results and updates audit logs
- Agents do NOT update audit logs directly

## Step 5: Final Summary

```markdown
## Hook Audit Complete

**Total audited**: X hooks
**By source**:
- Plugin ({name}): Y hooks
- Local: Z hooks

**Results**:
- Passed: Y hooks
- Passed with warnings: Z hooks
- Failed: W hooks

**Audit logs updated**:
- {plugin-path}/hooks/.audit-log.md
- .claude/hooks/.audit-log.md

### Details by Source

| Hook | Source | Result |
|------|--------|--------|
| hook-name | plugin | PASS |

**Next Steps**:
- Review detailed reports in `.claude/temp/`
- Address warnings and recommendations
- Re-audit failed hooks after fixes
```

## Important Notes

### Hook-Specific Considerations

- Hooks may be defined in hooks.json or settings.json
- Plugin hooks use different configuration patterns than local hooks
- Check both the hooks.json structure AND the individual hook scripts
- Test execution is important but may require manual verification

### Error Handling

If hooks.json doesn't exist:

- Check settings.json for hooks section
- If neither exists, skip that source

If hook script doesn't exist:

- Mark as critical failure in audit
- Continue auditing other hooks

### Cross-Platform Compatibility

- Use forward slashes `/` in paths
- Hook scripts may be Bash, Python, or Node.js
- Test on Windows (Git Bash/PowerShell), macOS, Linux
