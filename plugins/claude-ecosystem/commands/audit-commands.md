---
description: Audit Claude Code slash commands for quality, compliance, and maintainability
argument-hint: [command-name-1] [command-name-2] ... [--force] [--plugin-only] [--project-only] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(grep:*), Bash(test:*), Glob, Task, Skill
---

# Audit Commands Command

You are tasked with auditing Claude Code slash commands for quality, compliance, and maintainability.

## What Gets Audited

This command audits:

- YAML frontmatter validation (description, allowed-tools, argument-hint)
- Description quality (clear, concise, explains purpose)
- Tool restrictions appropriateness
- Argument handling patterns ($ARGUMENTS, $1, $2)
- File naming and organization
- Content structure and quality

## Command Arguments

This command accepts **command names and/or flags** as arguments:

- **No arguments**: Audit only commands that need it (modified since last audit, never audited, or >90 days old)
- **--force**: Audit ALL commands regardless of modification/audit status
- **--plugin-only**: Only audit plugin commands (skip project/user commands)
- **--project-only**: Only audit project commands (skip plugin/user commands)
- **One command name**: Audit a single command directly
- **Multiple command names**: Audit specified commands in parallel batches
- **Prefixed names**: `plugin:command-name` or `project:command-name` for explicit source targeting

**Argument format**:

- Command names first (e.g., `scrape-docs`, `plugin:audit-skills`)
- Flags last: `--force`, `--plugin-only`, `--project-only` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

**CRITICAL**: Always get the current UTC date before any operations.

1. **Get current date** using bash:

   ```bash
   date -u +"%Y-%m-%d"
   ```

2. **Store date** for use throughout execution: `audit_date = "YYYY-MM-DD"`

## Step 1: Discover Command Sources

Detect ALL editable command sources in the current repository:

### Detection Algorithm

```bash
# Check for marketplace (indicates multi-plugin repo)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Marketplace repo - discover all plugins with commands/
    echo "REPO_TYPE=marketplace"
fi

# Check for single plugin repo
if [ -f ".claude-plugin/plugin.json" ] && [ -d "./commands" ]; then
    # Plugin repo - commands in ./commands/
    echo "REPO_TYPE=plugin"
fi

# Check for project commands (always check)
if [ -d ".claude/commands" ]; then
    # Has project commands
    echo "HAS_PROJECT_COMMANDS=true"
fi
```

### Build Source List

Based on detection, build list of command sources:

**For marketplace repos:**

```text
For each plugin directory with .claude-plugin/plugin.json AND commands/:
  sources.append({
    type: "plugin",
    name: {plugin-name from plugin.json},
    path: "{plugin-dir}/commands/",
    audit_log: "{plugin-dir}/commands/.audit-log.md"
  })
```

**For plugin repos:**

```text
sources.append({
  type: "plugin",
  name: {plugin-name from plugin.json},
  path: "./commands/",
  audit_log: "./commands/.audit-log.md"
})
```

**For project commands (always if exists):**

```text
sources.append({
  type: "project",
  name: "project",
  path: ".claude/commands/",
  audit_log: ".claude/commands/.audit-log.md"
})
```

### Apply Filters

If `--plugin-only` flag: Filter sources to type="plugin" only
If `--project-only` flag: Filter sources to type="project" only

## Step 2: Parse Arguments and Read Context

1. **Parse flags** from arguments:
   - Check for `--force`, `--plugin-only`, `--project-only` (case-insensitive)
   - Extract command names from remaining arguments
   - Handle prefixed names: `plugin:name` or `project:name`

2. **Read audit logs** for each discovered source:
   - Parse tables to extract command names and last audit dates
   - Build map: `{source}:{command_name}: last_audit_date or null`

3. **Get all available commands** from each source:

   ```bash
   find {source_path} -name "*.md" -type f
   ```

## Step 3: Smart Prioritization (Smart Mode or Force Mode)

When **smart mode** (no command arguments) or **force mode** (`--force`), calculate audit priority:

### Priority Algorithm

For each command in each source:

1. **Get last modification date from git** (if in git repo):

   ```bash
   git log -1 --format=%cI {command_path}
   ```

   If not in git or fails, use file modification date.

2. **Get last audit date** from source's audit log (or null if never audited)

3. **Determine if audit needed** (skip in force mode):
   - IF `last_audit_date` is null: **NEEDS AUDIT** (never audited)
   - ELSE IF `last_mod_date` > `last_audit_date`: **NEEDS AUDIT** (modified since audit)
   - ELSE IF `(today - last_audit_date)` > 90 days: **NEEDS AUDIT** (stale audit)
   - ELSE: **SKIP** (recently audited and unchanged)

4. **Calculate priority score** (higher = audit sooner):

   ```text
   IF never_audited: priority_score = days_since_mod + 30
   ELSE IF modified_since_audit: priority_score = days_since_mod
   ELSE IF stale_audit: priority_score = days_since_mod / 2
   ```

5. **Sort by priority** (DESCENDING - oldest modifications FIRST)

### Present Audit Plan

Before executing, show user:

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**Sources discovered**:
- Plugin: {plugin-name} ({N} commands in {path})
- Project: ({N} commands in .claude/commands/)

**Total commands**: X
**Will audit**: Y {commands needing audit or all if force}

### Audit Queue (priority order):
1. [{source}] command-name-1 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
2. [{source}] command-name-2 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
...

**Batching strategy**: Y commands in N batches of 3-5

Proceeding with audit...
```

## Step 4: Execute Audits

### Single Command (One Argument)

1. **Invoke command-auditor subagent**:

   ```text
   Use the command-auditor subagent to audit the "{command-name}" command.

   Context:
   - Source: {plugin:{name} or project}
   - Command path: {full path to command file}
   - Last audit: {date} or "Never audited"
   - Last modified (git): {date}

   The subagent auto-loads command-development skill and handles the audit.
   ```

2. **Wait for completion**
3. **Update source's audit log**
4. **Report results**

### Multiple Commands (2+ Arguments or Batched Queue)

#### Batching Strategy

- **2 commands**: Sequential
- **3-5 commands**: Single parallel batch
- **6+ commands**: Multiple batches of 3-5 commands each

#### Parallel Batch Execution

For each batch:

1. **Spawn parallel command-auditor subagents** (one per command):

   ```text
   Use the command-auditor subagent to audit the "{command-name}" command.

   Context:
   - Source: {plugin:{name} or project}
   - Command path: {full path}
   - Last audit: {date} or "Never audited"
   - Last modified: {date}

   Output: Write findings to `.claude/temp/audit-{source}-{command-name}-latest.md`

   **IMPORTANT**: For parallel audits, do NOT update the audit log.
   Write findings to temp file only. Main conversation handles audit log updates.
   ```

2. **Wait for all agents in batch to complete**

3. **Collect results** from temp files

4. **Update audit logs** for each source:
   - Group completed audits by source
   - Update each source's audit log

5. **Report batch results**:

   ```markdown
   ## Batch {N} Results ({X} commands)

   ### Plugin Commands ({plugin-name})
   1. **command-name-1**: PASS
   2. **command-name-2**: PASS WITH WARNINGS

   ### Project Commands
   1. **command-name-3**: PASS
   2. **command-name-4**: FAIL (issues found)

   Details in `.claude/temp/audit-{source}-{command-name}-latest.md`
   ```

6. **If more batches remaining**: Proceed to next batch

## Step 5: Final Summary

After all audits complete:

```markdown
## Command Audit Complete

**Total audited**: X commands
**By source**:
- Plugin ({name}): Y commands
- Project: Z commands

**Results**:
- Passed: Y commands
- Passed with warnings: Z commands
- Failed: W commands (issues found, may need fixes)

**Audit logs updated**:
- {plugin-path}/commands/.audit-log.md
- .claude/commands/.audit-log.md

### Details by Source

#### Plugin Commands ({plugin-name})

| Command | Result |
|---------|--------|
| command-name | PASS |

#### Project Commands

| Command | Result |
|---------|--------|
| command-name | PASS |

**Next Steps**:
- Review detailed audit reports in `.claude/temp/audit-{source}-{command-name}-latest.md`
- Address warnings and recommendations
- Re-audit failed commands after fixes
```

## Important Notes

### Agent Coordination

**Main conversation thread manages**:

- Reading audit logs before audits
- Updating audit logs after audits (per source)
- Collecting and summarizing results

**Agents manage**:

- Individual command audits
- Writing findings to temp files
- Reporting scores and recommendations

**Agents do NOT**:

- Update audit logs (main thread only - prevents race conditions)
- Spawn sub-agents
- Wait for other agents

### Error Handling

If git log fails (file not in repo):

- Use current date as "last modified"
- Note in audit report

If audit log is missing:

- Create fresh audit log with header
- Continue with audit

### Cross-Platform Compatibility

- Use forward slashes `/` in paths
- Always use UTC dates (`date -u`)
- Test on Windows (Git Bash/PowerShell), macOS, Linux

## Example Usage

### Example 1: Audit All Commands in Marketplace Repo

```text
User: /audit-commands

Claude: Discovering command sources...

## Audit Plan

**Mode**: SMART
**Sources discovered**:
- Plugin: claude-ecosystem (15 commands in plugins/claude-ecosystem/commands/)
- Project: (3 commands in .claude/commands/)

**Total commands**: 18
**Will audit**: 5 (13 recently audited + unchanged)

### Audit Queue:
1. [plugin:claude-ecosystem] scrape-docs (modified: 2025-11-28, audit: Never)
2. [plugin:claude-ecosystem] refresh-docs (modified: 2025-11-29, audit: 2025-11-25)
...

Proceeding with Batch 1...
```

### Example 2: Audit Specific Plugin Command

```text
User: /audit-commands plugin:scrape-docs

Claude: Auditing plugin command "scrape-docs"...
[Spawns command-auditor subagent]

Audit complete for scrape-docs:
PASS (Score: 92/100)

Audit log updated: plugins/claude-ecosystem/commands/.audit-log.md
```

### Example 3: Audit Only Project Commands

```text
User: /audit-commands --project-only --force

Claude: Auditing all project commands (force mode)...
[Audits only .claude/commands/]
```
