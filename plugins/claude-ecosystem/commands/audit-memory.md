---
description: Audit Claude Code CLAUDE.md memory files for quality, compliance, and organization
argument-hint: [project | user | all] [--force] (optional)
allowed-tools: Read, Write, Edit, Bash(ls:*), Bash(git:*), Bash(test:*), Glob, Task, Skill
---

# Audit Memory Command

You are tasked with auditing Claude Code CLAUDE.md memory files for quality, compliance, and organization.

## What Gets Audited

This command audits:

- Import syntax (`@path/to/file.md`)
- Hierarchy compliance (enterprise > project > user)
- Circular import detection
- Size guidelines and progressive disclosure
- Content organization

## Command Arguments

This command accepts **scope selectors and/or flags** as arguments:

- **No arguments**: Audit all discoverable CLAUDE.md files
- **project**: Audit only project-level CLAUDE.md files
- **user**: Audit only `~/.claude/CLAUDE.md`
- **all**: Audit all CLAUDE.md files (project + user)
- **--force**: Audit regardless of modification status

**Argument format**:

- Scope first (e.g., `project`, `user`, `all`)
- Flags last: `--force` (case-insensitive)

## Step 0: Get Current Date (REQUIRED)

```bash
date -u +"%Y-%m-%d"
```

## Step 1: Discover CLAUDE.md Files

### Detection Algorithm

```bash
# Check for root CLAUDE.md
if [ -f "CLAUDE.md" ]; then
    echo "HAS_ROOT_CLAUDE_MD=true"
fi

# Check for .claude/CLAUDE.md
if [ -f ".claude/CLAUDE.md" ]; then
    echo "HAS_DOT_CLAUDE_MD=true"
fi

# Check for user CLAUDE.md
if [ -f "$HOME/.claude/CLAUDE.md" ]; then
    echo "HAS_USER_CLAUDE_MD=true"
fi

# Find any additional CLAUDE.md files in .claude/memory
find .claude/memory -name "*.md" 2>/dev/null | head -20
```

### Build Memory File List

```text
memory_files = []

if scope == "project" or scope == "all" or no_scope:
  # Root CLAUDE.md (highest priority for project)
  if exists("CLAUDE.md"):
    memory_files.append({
      scope: "project",
      level: "root",
      path: "CLAUDE.md",
      audit_log: ".claude-md-audit-log.md"
    })

  # .claude/CLAUDE.md
  if exists(".claude/CLAUDE.md"):
    memory_files.append({
      scope: "project",
      level: "dot-claude",
      path: ".claude/CLAUDE.md"
    })

  # Memory directory files
  for each file in ".claude/memory/*.md":
    memory_files.append({
      scope: "project",
      level: "memory",
      path: file_path
    })

if scope == "user" or scope == "all":
  if exists("~/.claude/CLAUDE.md"):
    memory_files.append({
      scope: "user",
      level: "user",
      path: "~/.claude/CLAUDE.md",
      audit_log: "~/.claude/.claude-md-audit-log.md"
    })
```

### Apply Scope Filter

Based on arguments, filter to requested scope(s).

## Step 2: Parse Arguments

1. Parse scope selector from arguments
2. Parse flags (--force)
3. Build filtered memory file list

## Step 3: Present Audit Plan

```markdown
## Audit Plan

**Mode**: {SMART/FORCE}
**Memory files discovered**: X

### Primary CLAUDE.md Files:
1. [project:root] CLAUDE.md (last modified: YYYY-MM-DD)
2. [user] ~/.claude/CLAUDE.md (last modified: YYYY-MM-DD)

### Imported Memory Files:
3. [project:memory] .claude/memory/workflows.md
4. [project:memory] .claude/memory/conventions.md
...

Proceeding with audit...
```

## Step 4: Execute Audits

### Parallel Batching Strategy

Group memory files into batches of **3-5** for parallel auditing:

```text
batches = chunk(memory_files, 5)

for batch in batches:
  # Spawn parallel subagents for this batch
  for file in batch:
    spawn memory-auditor subagent
  wait_for_all_in_batch()
```

### For Each Memory File

1. **Invoke memory-auditor subagent**:

   ```text
   Use the memory-auditor subagent to audit the memory file.

   Context:
   - Scope: {project/user}
   - Level: {root/dot-claude/memory/user}
   - File path: {full path}
   - Last audit: {date} or "Never audited"

   The subagent auto-loads memory-management skill and handles the audit.
   ```

2. Wait for batch completion
3. Update audit log (for primary files)
4. Report results

### Circular Import Detection

After individual audits, perform cross-file circular import check:

```text
1. Build import graph from all CLAUDE.md files
2. Detect cycles in the graph
3. Report any circular imports as CRITICAL issues
```

## Step 5: Final Summary

```markdown
## Memory Audit Complete

**Total audited**: X memory files
**By scope**:
- Project root: 1 file
- Project memory: Y files
- User: Z files

**Results**:
- Passed: A files
- Passed with warnings: B files
- Failed: C files

### Primary Files

| Scope | File | Result | Score |
|-------|------|--------|-------|
| project:root | CLAUDE.md | PASS | 88/100 |
| user | ~/.claude/CLAUDE.md | PASS WITH WARNINGS | 74/100 |

### Memory Directory Files

| File | Result | Issues |
|------|--------|--------|
| .claude/memory/workflows.md | PASS | - |
| .claude/memory/conventions.md | WARNINGS | Missing import |

### Circular Import Check

[X] No circular imports detected
OR
[!] CRITICAL: Circular imports detected:
    - CLAUDE.md -> memory/a.md -> memory/b.md -> CLAUDE.md

**Common Issues Found**:
- [List common issues across multiple files]

**Next Steps**:
- Fix circular imports (if any)
- Update broken import paths
- Apply progressive disclosure patterns
- Re-audit after changes
```

## Important Notes

### Import Syntax

Valid import syntax: `@path/to/file.md`

Examples:

- `@.claude/memory/workflows.md` (project-relative)
- `@~/.claude/CLAUDE.md` (user-level)

### Hierarchy Compliance

Memory files follow a hierarchy:

1. **Enterprise** (managed policies - highest precedence)
2. **Project root** (`CLAUDE.md`)
3. **Project dot-claude** (`.claude/CLAUDE.md`)
4. **User** (`~/.claude/CLAUDE.md` - lowest precedence)

Higher levels can override lower levels.

### Progressive Disclosure

Large CLAUDE.md files should use progressive disclosure:

- Keep root file focused (under ~50 lines ideally)
- Import detailed content from `.claude/memory/*.md`
- Load details just-in-time, not all upfront

### Size Guidelines

| File Type | Recommended Size |
| --------- | ---------------- |
| Root CLAUDE.md | < 50 lines core + imports |
| Memory imports | < 500 lines each |
| Total loaded | Context-dependent |

### Anti-Patterns

- **Circular imports**: A imports B imports A
- **Excessive nesting**: More than 3 levels deep
- **Duplicate content**: Same info in multiple files
- **Stale imports**: References to non-existent files
