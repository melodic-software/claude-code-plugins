# Temporary File Rules

Validation rules for `.claude/temp/**` files and temporary workspace management.

## Only Allowed Temp Location

- [ ] **All temporary files MUST be in .claude/temp/**
  - No temp files in repo root
  - No temp files in topic folders
  - No temp files in .claude/skills/ or other subdirectories
  - Exception: Files explicitly gitignored for specific purposes
  - Rationale: Repository cleanliness, consistent organization

**Detection Pattern:**

```bash
# BAD: Temp files in wrong locations
/test-script.py
/draft-docs.md
/.claude/skills/temp-notes.md

# GOOD: Temp files in correct location
/.claude/temp/2025-11-28_143022-explore-git-config.md
```

## Naming Convention

- [ ] **Follow standard naming pattern**
  - Pattern: `YYYY-MM-DD_HHmmss-{agent-type}-{topic}.md`
  - Date: ISO 8601 date format (YYYY-MM-DD)
  - Time: Compact 24-hour format (HHmmss)
  - Agent type: explore, plan, general, research, draft, etc.
  - Topic: Brief kebab-case description
  - Rationale: Chronological sorting, discoverability

**Detection Pattern:**

```markdown
<!-- GOOD: Proper naming -->
2025-11-28_143022-explore-git-config.md
2025-11-28_150000-plan-refactor-docs.md
2025-11-28_151530-research-nodejs-versions.md

<!-- BAD: Poor naming -->
temp.md
notes.md
scratch-work.md
untitled-1.md
```

## Flat Structure

- [ ] **No subdirectories within .claude/temp/**
  - All temp files at `.claude/temp/{filename}`
  - No nested folders like `.claude/temp/agents/` or `.claude/temp/2025-11/`
  - Flat structure with chronological naming enables sorting
  - Rationale: Simplicity, consistent organization

## UTC Timestamps Required

- [ ] **All timestamps MUST be UTC**
  - Format: `YYYY-MM-DD_HHmmss` in UTC timezone
  - Not local time (avoids timezone confusion)
  - ISO 8601 date portion for clarity
  - Rationale: Unambiguous temporal reference, sorting

**Detection Pattern:**

```markdown
<!-- GOOD: UTC timestamp -->
2025-11-28_143022-explore-git-config.md
Created at: 2025-11-28 14:30:22 UTC

<!-- BAD: Local time or ambiguous timestamp -->
2025-11-28_093022-explore-git-config.md (PST - ambiguous!)
```

## Cleanup Requirements

- [ ] **Temp files may persist if gitignored**
  - `.claude/temp/` is in `.gitignore`
  - Files here are ephemeral, not committed
  - Can remain after task completion
  - Rationale: Temporary workspace, not permanent storage

- [ ] **Non-gitignored temp files MUST be cleaned up**
  - If temp files created outside `.claude/temp/` and not gitignored
  - MUST be removed before task completion
  - Run `git status` to verify no untracked temp artifacts
  - Rationale: Repository cleanliness, version control hygiene

**Detection Pattern:**

```bash
# Before task completion, verify no stray temp files
git status

# Should NOT show:
# Untracked files:
#   test-script.py
#   draft-notes.md
#   experimental-config.json

# ONLY acceptable untracked files:
#   .claude/temp/2025-11-28_143022-explore-git-config.md (gitignored)
```

## Gitignored Status

- [ ] **.claude/temp/ directory is gitignored**
  - Verify `.gitignore` contains `.claude/temp/`
  - Files here never committed to version control
  - Safe for scratch work, agent communication
  - Rationale: Ephemeral workspace, not permanent docs

## Purpose and Lifecycle

- [ ] **Temp files serve specific purposes**
  - Agent-to-agent communication (passing context)
  - Research artifacts and exploration notes
  - Draft content before final placement
  - Scratch files for multi-step workflows
  - Rationale: Temporary workspace for intermediate state

- [ ] **Temp files have clear lifecycle**
  - Created: When agents need to pass info or store research
  - Used: Read by subsequent agents or main conversation
  - Cleaned: Periodically removed (manual or automated)
  - Never committed to repo
  - Rationale: Defined lifecycle, no permanent clutter

## Agent Communication Pattern

- [ ] **Use temp files for agent handoffs**
  - Agent 1 writes findings to `.claude/temp/{timestamp}-{type}-{topic}.md`
  - Agent 2 reads and continues work
  - Main conversation references temp file for context
  - Delete after handoff complete (if no longer needed)
  - Rationale: Cross-agent context sharing

**Detection Pattern:**

```markdown
<!-- Agent 1 creates -->
.claude/temp/2025-11-28_143022-explore-codebase-structure.md

<!-- Agent 2 references -->
Read `.claude/temp/2025-11-28_143022-explore-codebase-structure.md`
Continue analysis based on findings...

<!-- Main conversation -->
Agent 1 explored codebase (see temp file)
Agent 2 completed refactoring plan
Temp file no longer needed - can be deleted
```

## Anti-Patterns

- [ ] **Avoid generic or misleading names**
  - ❌ `notes.md` (not descriptive)
  - ❌ `temp.md` (not timestamped)
  - ❌ `draft.md` (missing agent type and topic)
  - ✅ `2025-11-28_143022-draft-skill-documentation.md`
  - Rationale: Discoverability, clarity of purpose

- [ ] **Avoid committing temp files**
  - Temp files are ephemeral, not documentation
  - If content is valuable, move to proper location
  - Don't add `.claude/temp/*` files to git
  - Rationale: Version control hygiene

---

**Tier:** 4 (CLAUDE.md-specific)
**Applies To:** `.claude/temp/**` files and temporary workspace
**Last Updated:** 2025-11-28
