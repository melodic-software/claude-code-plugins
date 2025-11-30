---
description: Audit Claude Code skills for quality, compliance, delegation pattern, and maintainability
argument-hint: [skill-name-1] [skill-name-2] ... [--force] [--plugin-only] [--project-only] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(grep:*), Bash(test:*), Glob, Task, Skill
---

# Audit Skills Command

You are tasked with auditing Claude Code skills for quality, compliance, and maintainability.

## Audit Types

This command performs TWO types of audits based on skill nature:

### Type A: Standard Skill Audit

For regular skills (git-setup, markdown-linting, etc.):

- YAML frontmatter validation
- Naming conventions
- File structure: scripts/, references/, assets/ organization
- Progressive disclosure compliance
- Documentation quality and completeness
- Activation testing
- Best practices adherence

### Type B: Meta-Skill Audit (Delegation Pattern)

For Claude Code meta-skills (skill-development, docs-management, etc.):

- **Zero duplication check**: No official documentation copied into skill
- **Delegation pattern**: All documentation queries go to docs-management skill
- **Metadata-only compliance**: Skill contains only keywords, workflows, decision trees
- **Reference organization**: Proper use of references/ subdirectories
- **Example compliance**: Follow skill-development skill as reference implementation

**Auto-detection**: Command detects skill type automatically based on name/description.

## Command Arguments

This command accepts **skill names and/or flags** as arguments:

- **No arguments**: Audit only skills that need it (modified since last audit, never audited, or >90 days old)
- **--force**: Audit ALL skills regardless of modification/audit status
- **--plugin-only**: Only audit plugin skills (skip project skills)
- **--project-only**: Only audit project skills (skip plugin skills)
- **One skill name**: Audit a single skill directly
- **Multiple skill names**: Audit specified skills in parallel batches
- **Prefixed names**: `plugin:skill-name` or `project:skill-name` for explicit source targeting

**Argument format**:

- Skill names first (e.g., `skill-development`, `git-setup`, `plugin:docs-management`)
- Flags last: `--force`, `--plugin-only`, `--project-only` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

**CRITICAL**: Always get the current UTC date before any operations.

1. **Get current date** using bash:

   ```bash
   date -u +"%Y-%m-%d"
   ```

2. **Store date** for use throughout execution: `audit_date = "YYYY-MM-DD"`

## Step 1: Discover Skill Sources

Detect ALL editable skill sources in the current repository:

### Detection Algorithm

```bash
# Check for marketplace (indicates multi-plugin repo)
if [ -f "marketplace.json" ] || [ -f ".claude-plugin/marketplace.json" ]; then
    # Marketplace repo - discover all plugins with skills/
    echo "REPO_TYPE=marketplace"
fi

# Check for single plugin repo
if [ -f ".claude-plugin/plugin.json" ] && [ -d "./skills" ]; then
    # Plugin repo - skills in ./skills/
    echo "REPO_TYPE=plugin"
fi

# Check for project skills (always check)
if [ -d ".claude/skills" ]; then
    # Has project skills
    echo "HAS_PROJECT_SKILLS=true"
fi
```

### Build Source List

Based on detection, build list of skill sources:

**For marketplace repos:**

```text
For each plugin directory with .claude-plugin/plugin.json AND skills/:
  sources.append({
    type: "plugin",
    name: {plugin-name from plugin.json},
    path: "{plugin-dir}/skills/",
    audit_log: "{plugin-dir}/skills/.audit-log.md"
  })
```

**For plugin repos:**

```text
sources.append({
  type: "plugin",
  name: {plugin-name from plugin.json},
  path: "./skills/",
  audit_log: "./skills/.audit-log.md"
})
```

**For project skills (always if exists):**

```text
sources.append({
  type: "project",
  name: "project",
  path: ".claude/skills/",
  audit_log: ".claude/skills/.audit-log.md"
})
```

### Apply Filters

If `--plugin-only` flag: Filter sources to type="plugin" only
If `--project-only` flag: Filter sources to type="project" only

## Step 2: Parse Arguments and Read Context

1. **Parse flags** from arguments:
   - Check for `--force`, `--plugin-only`, `--project-only` (case-insensitive)
   - Extract skill names from remaining arguments
   - Handle prefixed names: `plugin:name` or `project:name`

2. **Read audit logs** for each discovered source:
   - Parse tables to extract skill names and last audit dates
   - Build map: `{source}:{skill_name}: last_audit_date or null`

3. **Get all available skills** from each source:

   ```bash
   ls -1d {source_path}*/
   ```

## Step 3: Smart Prioritization (Smart Mode or Force Mode)

When **smart mode** (no skill arguments) or **force mode** (`--force`), calculate audit priority:

### Priority Algorithm

For each skill in each source:

1. **Get last modification date from git** (if in git repo):

   ```bash
   git log -1 --format=%cI {skill_path}
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
- Plugin: {plugin-name} ({N} skills in {path})
- Project: ({N} skills in .claude/skills/)

**Total skills**: X
**Will audit**: Y {skills needing audit or all if force}

### Audit Queue (priority order):
1. [{source}] skill-name-1 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
2. [{source}] skill-name-2 (last modified: YYYY-MM-DD, last audit: YYYY-MM-DD or Never)
...

**Batching strategy**: Y skills in N batches of 3-5

Proceeding with audit...
```

## Step 4: Execute Audits

### Skill Type Detection

Before auditing each skill, determine audit type:

1. **Read SKILL.md** frontmatter and first 50 lines
2. **Detect meta-skill** (Type B) if ANY of:
   - Skill name contains: `claude`, `code`, `skill`, `docs`, `meta`
   - Description mentions: `Claude Code`, `meta-skill`, `documentation`, `official docs`
   - Content has delegation patterns
3. **Default to standard skill** (Type A) otherwise

### Single Skill (One Argument)

1. **Detect skill type** (A or B)
2. **Invoke skill-auditor subagent**:

   ```text
   Use the skill-auditor subagent to audit the "{skill-name}" skill.

   Context:
   - Source: {plugin:{name} or project}
   - Skill path: {full path to skill directory}
   - Audit type: {Type A (Standard) or Type B (Meta-Skill)}
   - Last audit: {date} or "Never audited"
   - Last modified (git): {date}

   The subagent auto-loads skill-development skill and handles the audit.
   ```

3. **Wait for completion**
4. **Update source's audit log**
5. **Report results**

### Multiple Skills (2+ Arguments or Batched Queue)

#### Batching Strategy

- **2 skills**: Sequential
- **3-5 skills**: Single parallel batch
- **6+ skills**: Multiple batches of 3-5 skills each

#### Parallel Batch Execution

For each batch:

1. **Detect skill types** for all skills in batch

2. **Spawn parallel skill-auditor subagents** (one per skill):

   ```text
   Use the skill-auditor subagent to audit the "{skill-name}" skill.

   Context:
   - Source: {plugin:{name} or project}
   - Skill path: {full path}
   - Audit type: {Type A or Type B}
   - Last audit: {date} or "Never audited"
   - Last modified: {date}

   Output: Write findings to `.claude/temp/audit-{source}-{skill-name}-latest.md`

   **IMPORTANT**: For parallel audits, do NOT update the audit log.
   Write findings to temp file only. Main conversation handles audit log updates.
   ```

3. **Wait for all agents in batch to complete**

4. **Collect results** from temp files

5. **Update audit logs** for each source:
   - Group completed audits by source
   - Update each source's audit log

6. **Report batch results**:

   ```markdown
   ## Batch {N} Results ({X} skills)

   ### Plugin Skills ({plugin-name})
   1. **skill-name-1** (Type B): PASS
   2. **skill-name-2** (Type B): PASS WITH WARNINGS

   ### Project Skills
   1. **skill-name-3** (Type A): PASS
   2. **skill-name-4** (Type A): FAIL (issues fixed)

   Details in `.claude/temp/audit-{source}-{skill-name}-latest.md`
   ```

7. **If more batches remaining**: Proceed to next batch

## Step 5: Final Summary

After all audits complete:

```markdown
## Skill Audit Complete

**Total audited**: X skills
**By source**:
- Plugin ({name}): Y skills
- Project: Z skills

**By type**:
- Type A (Standard): Y skills
- Type B (Meta-Skill): Z skills

**Results**:
- Passed: Y skills
- Passed with warnings: Z skills
- Failed: W skills (issues fixed, may need re-audit)

**Audit logs updated**:
- {plugin-path}/skills/.audit-log.md
- .claude/skills/.audit-log.md

### Details by Source

#### Plugin Skills ({plugin-name})

| Skill | Type | Result |
|-------|------|--------|
| skill-name | B | PASS |

#### Project Skills

| Skill | Type | Result |
|-------|------|--------|
| skill-name | A | PASS |

**Next Steps**:
- Review detailed audit reports in `.claude/temp/audit-{source}-{skill-name}-latest.md`
- Address warnings and recommendations
- Re-audit failed skills after fixes
```

## Important Notes

### Agent Coordination

**Main conversation thread manages**:
- Reading audit logs before audits
- Updating audit logs after audits (per source)
- Collecting and summarizing results

**Agents manage**:
- Individual skill audits
- Writing findings to temp files
- Fixing critical issues during audit

**Agents do NOT**:
- Update audit logs (main thread only - prevents race conditions)
- Spawn sub-agents
- Wait for other agents

### Error Handling

If git log fails (file not in repo):
- Use current date as "last modified"
- Note in audit report

If audit log is missing:
- Create fresh audit log with all skills, empty dates
- Continue with audit

### Cross-Platform Compatibility

- Use forward slashes `/` in paths
- Always use UTC dates (`date -u`)
- Test on Windows (Git Bash/PowerShell), macOS, Linux

## Example Usage

### Example 1: Audit All Skills in Marketplace Repo

```text
User: /audit-skills

Claude: Discovering skill sources...

## Audit Plan

**Mode**: SMART
**Sources discovered**:
- Plugin: claude-ecosystem (17 skills in plugins/claude-ecosystem/skills/)
- Project: (3 skills in .claude/skills/)

**Total skills**: 20
**Will audit**: 5 (15 recently audited + unchanged)

### Audit Queue:
1. [plugin:claude-ecosystem] skill-development (modified: 2025-11-28, audit: Never)
2. [plugin:claude-ecosystem] docs-management (modified: 2025-11-29, audit: 2025-11-25)
3. [project] git-commit (modified: 2025-11-30, audit: Never)
...

Proceeding with Batch 1...
```

### Example 2: Audit Specific Plugin Skill

```text
User: /audit-skills plugin:docs-management

Claude: Auditing plugin skill "docs-management"...
[Spawns skill-auditor subagent]

Audit complete for docs-management:
PASS (excellent delegation pattern compliance)

Audit log updated: plugins/claude-ecosystem/skills/.audit-log.md
```

### Example 3: Audit Only Project Skills

```text
User: /audit-skills --project-only --force

Claude: Auditing all project skills (force mode)...
[Audits only .claude/skills/]
```
