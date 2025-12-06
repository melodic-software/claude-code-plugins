---
description: Audit Claude Code subagents for quality, compliance, and maintainability
argument-hint: [agent-name-1] [agent-name-2] ... [--force] [--plugin-only] [--project-only] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(grep:*), Bash(test:*), Glob, Task, Skill
---

# Audit Agents Command

You are tasked with auditing Claude Code subagents for quality, compliance, and maintainability.

## What Gets Audited

This command audits:

- YAML frontmatter validation (name, description, tools, model)
- Name constraints (lowercase, hyphens, max 64 chars, no reserved words)
- Description quality (third person, when-to-use guidance, delegation triggers)
- Tool access appropriateness
- Model selection guidance (haiku/sonnet/opus/inherit)
- Undocumented features (color, permissionMode, skills)

## Command Arguments

This command accepts **agent names and/or flags** as arguments:

- **No arguments**: Audit only agents that need it (modified since last audit, never audited, or >90 days old)
- **--force**: Audit ALL agents regardless of modification/audit status
- **--plugin-only**: Only audit plugin agents (skip project/user agents)
- **--project-only**: Only audit project agents (skip plugin/user agents)
- **One agent name**: Audit a single agent directly
- **Multiple agent names**: Audit specified agents in parallel batches
- **Prefixed names**: `plugin:agent-name` or `project:agent-name` for explicit source targeting

**Argument format**:

- Agent names first (e.g., `skill-auditor`, `plugin:code-reviewer`)
- Flags last: `--force`, `--plugin-only`, `--project-only` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

**CRITICAL**: Always get the current UTC date before any operations.

1. **Get current date** using bash:

   ```bash
   date -u +"%Y-%m-%d"
   ```

2. **Store date** for use throughout execution: `audit_date = "YYYY-MM-DD"`

## Step 1: Discover Agent Sources

Detect ALL editable agent sources in the current repository:

### Detection Algorithm

```bash
# Check for marketplace (indicates multi-plugin repo)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Marketplace repo - discover all plugins with agents/
    echo "REPO_TYPE=marketplace"
fi

# Check for single plugin repo
if [ -f ".claude-plugin/plugin.json" ] && [ -d "./agents" ]; then
    # Plugin repo - agents in ./agents/
    echo "REPO_TYPE=plugin"
fi

# Check for project agents (always check)
if [ -d ".claude/agents" ]; then
    # Has project agents
    echo "HAS_PROJECT_AGENTS=true"
fi
```

### Build Source List

Based on detection, build list of agent sources:

**For marketplace repos:**

```text
For each plugin directory with .claude-plugin/plugin.json AND agents/:
  sources.append({
    type: "plugin",
    name: {plugin-name from plugin.json},
    path: "{plugin-dir}/agents/",
    audit_log: "{plugin-dir}/agents/.audit-log.md"
  })
```

**For plugin repos:**

```text
sources.append({
  type: "plugin",
  name: {plugin-name from plugin.json},
  path: "./agents/",
  audit_log: "./agents/.audit-log.md"
})
```

**For project agents (always if exists):**

```text
sources.append({
  type: "project",
  name: "project",
  path: ".claude/agents/",
  audit_log: ".claude/agents/.audit-log.md"
})
```

### Apply Filters

If `--plugin-only` flag: Filter sources to type="plugin" only
If `--project-only` flag: Filter sources to type="project" only

## Step 2: Parse Arguments and Read Context

1. **Parse flags** from arguments:
   - Check for `--force`, `--plugin-only`, `--project-only` (case-insensitive)
   - Extract agent names from remaining arguments
   - Handle prefixed names: `plugin:name` or `project:name`

2. **Read audit logs** for each discovered source:
   - Parse tables to extract agent names and last audit dates
   - Build map: `{source}:{agent_name}: last_audit_date or null`

3. **Get all available agents** from each source:

   ```bash
   find {source_path} -name "*.md" -type f
   ```

## Step 3: Smart Prioritization (Smart Mode or Force Mode)

When **smart mode** (no agent arguments) or **force mode** (`--force`), calculate audit priority:

### Priority Algorithm

For each agent in each source:

1. **Get last modification date from git** (if in git repo):

   ```bash
   git log -1 --format=%cI {agent_path}
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
- Plugin: {plugin-name} ({N} agents in {path})
- Project: ({N} agents in .claude/agents/)

**Total agents**: X
**Will audit**: Y {agents needing audit or all if force}

### Audit Queue (priority order):
1. [{source}] agent-name-1 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
2. [{source}] agent-name-2 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
...

**Batching strategy**: Y agents in N batches of 3-5

Proceeding with audit...
```

## Step 4: Execute Audits

### Single Agent (One Argument)

1. **Invoke agent-auditor subagent**:

   ```text
   Use the agent-auditor subagent to audit the "{agent-name}" agent.

   Context:
   - Source: {plugin:{name} or project}
   - Agent path: {full path to agent file}
   - Last audit: {date} or "Never audited"
   - Last modified (git): {date}

   The subagent auto-loads subagent-development skill and handles the audit.
   ```

2. **Wait for completion**
3. **Update source's audit log**
4. **Report results**

### Multiple Agents (2+ Arguments or Batched Queue)

#### Batching Strategy

- **2 agents**: Sequential
- **3-5 agents**: Single parallel batch
- **6+ agents**: Multiple batches of 3-5 agents each

#### Parallel Batch Execution

For each batch:

1. **Spawn parallel agent-auditor subagents** (one per agent):

   ```text
   Use the agent-auditor subagent to audit the "{agent-name}" agent.

   Context:
   - Source: {plugin:{name} or project}
   - Agent path: {full path}
   - Last audit: {date} or "Never audited"
   - Last modified: {date}

   Output: Write findings to `.claude/temp/audit-{source}-{agent-name}-latest.md`

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
   ## Batch {N} Results ({X} agents)

   ### Plugin Agents ({plugin-name})
   1. **agent-name-1**: PASS
   2. **agent-name-2**: PASS WITH WARNINGS

   ### Project Agents
   1. **agent-name-3**: PASS
   2. **agent-name-4**: FAIL (issues found)

   Details in `.claude/temp/audit-{source}-{agent-name}-latest.md`
   ```

6. **If more batches remaining**: Proceed to next batch

## Step 5: Final Summary

After all audits complete:

```markdown
## Agent Audit Complete

**Total audited**: X agents
**By source**:
- Plugin ({name}): Y agents
- Project: Z agents

**Results**:
- Passed: Y agents
- Passed with warnings: Z agents
- Failed: W agents (issues found, may need fixes)

**Audit logs updated**:
- {plugin-path}/agents/.audit-log.md
- .claude/agents/.audit-log.md

### Details by Source

#### Plugin Agents ({plugin-name})

| Agent | Result |
|-------|--------|
| agent-name | PASS |

#### Project Agents

| Agent | Result |
|-------|--------|
| agent-name | PASS |

**Next Steps**:
- Review detailed audit reports in `.claude/temp/audit-{source}-{agent-name}-latest.md`
- Address warnings and recommendations
- Re-audit failed agents after fixes
```

## Important Notes

### Agent Coordination

**Main conversation thread manages**:

- Reading audit logs before audits
- Updating audit logs after audits (per source)
- Collecting and summarizing results

**Agents manage**:

- Individual agent audits
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

### Example 1: Audit All Agents in Marketplace Repo

```text
User: /audit-agents

Claude: Discovering agent sources...

## Audit Plan

**Mode**: SMART
**Sources discovered**:
- Plugin: claude-ecosystem (12 agents in plugins/claude-ecosystem/agents/)
- Plugin: code-quality (3 agents in plugins/code-quality/agents/)
- Project: (2 agents in .claude/agents/)

**Total agents**: 17
**Will audit**: 4 (13 recently audited + unchanged)

### Audit Queue:
1. [plugin:claude-ecosystem] docs-researcher (modified: 2025-11-28, audit: Never)
2. [plugin:claude-ecosystem] command-auditor (modified: 2025-12-05, audit: Never)
...

Proceeding with Batch 1...
```

### Example 2: Audit Specific Plugin Agent

```text
User: /audit-agents plugin:skill-auditor

Claude: Auditing plugin agent "skill-auditor"...
[Spawns agent-auditor subagent]

Audit complete for skill-auditor:
PASS (Score: 95/100)

Audit log updated: plugins/claude-ecosystem/agents/.audit-log.md
```

### Example 3: Audit Only Project Agents

```text
User: /audit-agents --project-only --force

Claude: Auditing all project agents (force mode)...
[Audits only .claude/agents/]
```
