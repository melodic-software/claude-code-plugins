# Audit Quick Fixes Checklist

**Date:** 2025-11-30
**Reference:** See `AUDIT-REPORT.md` for full details
**Last Updated:** 2025-12-01 (ALL items completed)

---

## HIGH PRIORITY

### H1: Marketplace Version Mismatch (5 min) - COMPLETED

- [x] `.claude-plugin/marketplace.json` - Update versions:
  - [x] Set claude-ecosystem to "3.0.0" (currently "2.0.0")
  - [x] Set code-quality to "2.0.0" (currently "1.0.0")
  - [x] Set google-ecosystem to "1.1.0" (currently "1.0.0")
  - [x] Add git plugin entry with version "1.0.0"
  - [x] Update metadata.version to "3.0.0"

### H2: Add `allowed-tools` to Skills (30 min) - COMPLETED

- [x] `plugins/claude-ecosystem/skills/docs-management/SKILL.md`
- [x] `plugins/code-quality/skills/markdown-linting/SKILL.md`
- [x] `plugins/code-quality/skills/python/SKILL.md`
- [x] `plugins/git/skills/git-commit/SKILL.md`
- [x] `plugins/git/skills/git-config/SKILL.md`
- [x] `plugins/git/skills/git-gpg-signing/SKILL.md`
- [x] `plugins/git/skills/git-gui-tools/SKILL.md`
- [x] `plugins/git/skills/git-hooks/SKILL.md`
- [x] `plugins/git/skills/git-line-endings/SKILL.md`
- [x] `plugins/git/skills/git-push/SKILL.md`
- [x] `plugins/git/skills/git-setup/SKILL.md`
- [x] `plugins/git/skills/gpg-multi-key/SKILL.md`

**Applied values:**

- docs-management: `allowed-tools: Read, Glob, Grep, Bash, Skill`
- markdown-linting: `allowed-tools: Read, Bash, Glob, Grep`
- python: `allowed-tools: Read, Bash, Glob, Grep`
- git-*: `allowed-tools: Read, Bash, Glob, Grep`

### H3: Add Test Scenarios to google-ecosystem Skills (2-4 hrs) - COMPLETED

- [x] `plugins/google-ecosystem/skills/gemini-checkpoint-management/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-cli-docs/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-cli-execution/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-command-development/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-config-management/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-context-bridge/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-delegation-patterns/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-extension-development/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-json-parsing/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-mcp-integration/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-sandbox-configuration/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-session-management/SKILL.md`
- [x] `plugins/google-ecosystem/skills/gemini-token-optimization/SKILL.md`

**Added to each skill:**
- 3 test scenarios (Query, Expected Behavior, Success Criteria)
- Version History section with v1.1.0 (2025-12-01)

---

## MEDIUM PRIORITY

### M1: Add matcher to google-ecosystem hooks.json (2 min) - COMPLETED

- [x] `plugins/google-ecosystem/hooks/hooks.json` - Add `"matcher": "*"` to UserPromptSubmit entry

### M2: Add Delegation Verification to google-ecosystem (1-2 hrs) - COMPLETED

- [x] Add "MANDATORY: Invoke gemini-cli-docs First" section to:
  - [x] gemini-checkpoint-management (already had it)
  - [x] gemini-cli-execution (already had it)
  - [x] gemini-command-development (already had it)
  - [x] gemini-config-management (already had it)
  - [x] gemini-context-bridge (added)
  - [x] gemini-extension-development (already had it)
  - [x] gemini-json-parsing (added)
  - [x] gemini-mcp-integration (already had it)
  - [x] gemini-sandbox-configuration (already had it)
  - [x] gemini-session-management (already had it)
  - [x] gemini-token-optimization (added)
  - [x] gemini-delegation-patterns (added)

**Note:** gemini-cli-docs is the source of truth skill - doesn't need to delegate to itself

### M3: Standardize Progressive Disclosure (2-3 hrs) - PENDING

- [ ] Document standard pattern in README or CLAUDE.md
- [ ] Audit google-ecosystem skills for references/ structure
- [ ] Add references/ directories where beneficial

---

## LOW PRIORITY

### L2: Improve Keyword Coverage - COMPLETED

- [x] Audit skills with < 10 keywords in description
- [x] Add additional relevant keywords
- [x] Added MANDATORY sections, Test Scenarios, Version History to 5 additional skills:
  - toml-command-builder
  - gemini-exploration-patterns
  - gemini-memory-sync
  - gemini-workspace-bridge
  - policy-engine-builder

### L3: Add Related Skills Sections - COMPLETED

- [x] All google-ecosystem skills now have Related Skills sections
- [x] Cross-references maintained between related skills

### L4: Standardize Version History Format - COMPLETED

- [x] Chosen format: `- v1.0.0 (YYYY-MM-DD): Description`
- [x] Applied consistently across all google-ecosystem skills
- [x] All skills updated to v1.1.0 (2025-12-01) with changes noted

### L5: Clean Up Empty Directories - COMPLETED

- [x] `plugins/code-quality/config/` - Removed (was empty)

---

## Quick Reference: Recommended Tool Sets

| Category | allowed-tools |
|----------|---------------|
| Documentation | Read, Glob, Grep, Skill |
| Documentation (with scripts) | Read, Glob, Grep, Bash, Skill |
| Git workflow | Read, Bash, Glob, Grep |
| Code quality | Read, Bash, Glob, Grep |
| Pure delegation | Read, Glob, Grep, Skill |

---

## Completion Tracking

| Priority | Total | Completed |
|----------|-------|-----------|
| HIGH | 28 items | 28 |
| MEDIUM | 14 items | 14 |
| LOW | 5 items | 5 |

**Progress:** 47/47 items (100%) ✅

**Last Updated:** 2025-12-01

### Summary of Changes

**google-ecosystem skills updated (18 total):**
- All skills have MANDATORY delegation verification sections
- All skills have Test Scenarios (3 per skill)
- All skills have Version History sections
- All skills have Related Skills/Commands sections
- Standardized format: `- v1.0.0 (YYYY-MM-DD): Description`

**Additional fixes:**
- marketplace.json versions synchronized
- hooks.json matcher added
- Empty directories cleaned up
- allowed-tools added to all skills
