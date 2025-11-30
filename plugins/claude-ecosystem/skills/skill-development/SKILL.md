---
name: skill-development
description: Comprehensive meta-skill for creating, managing, validating, auditing, and distributing Claude Code skills. Provides skill templates, creation workflows, validation patterns, audit checklists, naming conventions, YAML frontmatter guidance, progressive disclosure examples, and best practices lookup. Use when creating new skills, validating existing skills, auditing skill quality, understanding skill architecture, needing skill templates, learning about YAML frontmatter requirements, progressive disclosure patterns, tool restrictions (allowed-tools), skill composition, skill naming conventions, or troubleshooting skill activation issues. Delegates to docs-management skill for official documentation.
allowed-tools: Read, Glob, Grep, Skill
---

# Skills Meta

## 🚨 MANDATORY: Invoke docs-management First

> **STOP - Before providing ANY response about Claude Code skills:**
>
> 1. **INVOKE** `docs-management` skill
> 2. **QUERY** using keywords: skills, skill creation, YAML frontmatter, progressive disclosure, skill best practices, or related topics
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded
>
> **Skipping this step results in outdated or incorrect information.**

### Verification Checkpoint

Before responding, verify:

- [ ] Did I invoke docs-management skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

If ANY checkbox is unchecked, STOP and invoke docs-management first.

## Overview

This meta-skill provides workflows, templates, keyword registries, and patterns for working with Claude Code skills. It does NOT duplicate official documentation - instead, it teaches you how to efficiently query the `docs-management` skill for any skills-related information you need.

**What this skill provides:**

- Skill template (5 structural patterns to choose from)
- Creation and validation workflows
- Keyword registry for efficient documentation lookups
- Naming conventions and common patterns
- Quick decision trees for navigation

**What this skill does NOT provide:**

- Duplicated official documentation (use `docs-management` skill instead)
- YAML frontmatter specifications (query `docs-management`)
- Progressive disclosure details (query `docs-management`)
- Complete best practices lists (query `docs-management`)

## When to Use This Skill

This skill should be used when:

- **Creating a new skill** → Provides template and creation workflow
- **Validating an existing skill** → Provides validation workflow and patterns
- **Auditing skill quality** → Provides comprehensive audit checklist and workflow
- **Understanding skill architecture** → Directs you to right official docs
- **Needing skill templates** → Provides 5 structural pattern options
- **Learning YAML frontmatter** → Shows you how to query docs-management
- **Troubleshooting activation** → Provides diagnostic patterns
- **Distributing skills** → Provides distribution workflow

## Quick Decision Tree

**What do you want to do?**

1. **Create a new skill from scratch** → See [workflows/creating-skills-workflow.md](references/workflows/creating-skills-workflow.md)
2. **Validate an existing skill** → See [workflows/validating-skills-workflow.md](references/workflows/validating-skills-workflow.md)
3. **Audit skill quality and compliance** → See [quality/skill-audit-guide.md](references/quality/skill-audit-guide.md) or use `/audit-skills` command
4. **Test skill activation** → See [workflows/testing-skills-workflow.md](references/workflows/testing-skills-workflow.md)
5. **Share or distribute a skill** → See [workflows/distributing-skills-workflow.md](references/workflows/distributing-skills-workflow.md)
6. **Understand skill architecture** → Query `docs-management` for "agent skills architecture progressive disclosure"
7. **Fix activation issues** → See Troubleshooting section below

## Official Documentation Discovery

### How to Query docs-management for Skills Documentation

The `docs-management` skill contains all official Claude Code skills documentation. Use natural language queries to access it:

**For creation guidance:**

```text
Find documentation about creating skills with best practices
```

**For YAML frontmatter requirements:**

```text
Locate the official YAML frontmatter specification for skills
```

**For progressive disclosure patterns:**

```text
Get the official progressive disclosure documentation for skills
```

**For tool restrictions:**

```text
Find documentation about allowed-tools configuration for skills
```

### Keyword Registry for Efficient Searches

Use these keyword combinations with the `docs-management` skill for specific topics:

**Creation & Structure:**

- Keywords: `skills`, `skill creation`, `skill structure`, `YAML frontmatter`
- Use case: Understanding how to create skills and required structure

**Validation & Quality:**

- Keywords: `skill validation`, `skill best practices`, `skill patterns`
- Use case: Ensuring skill quality and following conventions

**Architecture & Patterns:**

- Keywords: `progressive disclosure`, `skill composition`, `agent skills`
- Use case: Understanding architectural patterns and advanced topics

**Tool Configuration:**

- Keywords: `allowed-tools`, `tool restrictions`, `skills`
- Use case: Configuring which tools Claude can use within a skill

**Activation & Discovery:**

- Keywords: `skill description`, `skill activation`, `skill triggers`
- Use case: Ensuring Claude discovers and uses your skill correctly

**Distribution & Sharing:**

- Keywords: `plugin skills`, `skill locations`, `personal skills`, `project skills`
- Use case: Understanding where skills live and how to share them

## Creating Skills Workflow (Quick Reference)

1. **Choose Template:** Use `assets/skill-template/` (5 structural patterns: workflow, task, reference, capabilities, validation)
2. **Query Official Docs:** Load current requirements from docs-management
3. **Complete TODOs:** Fill in frontmatter, content, examples
4. **Validate:** Check frontmatter, naming, structure, activation

**Full workflow:** [references/workflows/creating-skills-workflow.md](references/workflows/creating-skills-workflow.md)

## Validating Skills Workflow (Quick Reference)

**YAML Frontmatter:**

- `name`: Lowercase, hyphens only, max 64 chars, matches directory
- `description`: Max 1024 chars, includes what + when to use

**Naming Convention:** Use "The Sentence Test" - "I'm going to reach for the [skill-name] skill" should sound natural

**Activation Testing:** Test with direct mention, domain mention, task mention, file type mention

**Full workflow:** [references/workflows/validating-skills-workflow.md](references/workflows/validating-skills-workflow.md)

## Auditing Skills Workflow (Quick Reference)

**Use `/audit-skills` command for automated auditing:**

- Single skill: `/audit-skills skill-name`
- Multiple skills: `/audit-skills skill-1 skill-2`
- All skills: `/audit-skills --all`
- Smart prioritization: `/audit-skills --smart`

**Manual audit checklist:** [references/quality/skill-audit-guide.md](references/quality/skill-audit-guide.md)

## SKILL.md Length Guidance

**Official Recommendation:** Keep SKILL.md body under 500 lines for optimal performance.

**This is GUIDANCE, not a hard rule.** The 500-line recommendation exists because:

1. Context window is a shared resource (competes with conversation history, other skills)
2. Concise skills load faster and use fewer tokens
3. Progressive disclosure prevents token bloat

**When exceeding 500 lines may be acceptable:**

- Complex skills with genuinely essential content (no fluff)
- Domain-specific skills where core workflows require detail
- Skills where splitting would harm usability or add navigation overhead

**Tradeoff Framework:**

| Factor | Stay Under 500 | Exceed If Necessary |
| ------ | -------------- | ------------------- |
| Content type | Platform-specific, examples, troubleshooting | Core workflows, critical requirements |
| Loading frequency | Rarely used sections | Always needed on every invocation |
| Alternative | Can extract to references/ | Extraction would harm usability |
| Token cost | High (verbose explanations) | Low (essential, concise content) |

**Decision Rule:** If content is needed on EVERY skill invocation AND cannot be made more concise, it may stay in SKILL.md even if it exceeds 500 lines. Conditional content should ALWAYS go to references/.

**Query docs-management for current official guidance:**

```text
Find SKILL.md size recommendations and token budget guidance
```

## Common Patterns

### Progressive Disclosure Pattern

Load content in layers: Metadata → SKILL.md body → references/ files

**Key Context Clues for Good Progressive Disclosure:**

1. **Clear reference links**: Each reference file should have explicit pointers from SKILL.md
2. **Descriptive filenames**: Use names like `troubleshooting.md`, `platform-windows.md` (not `doc1.md`)
3. **When-to-load guidance**: SKILL.md should indicate when each reference is needed
4. **One level deep**: References should NOT link to other references (Claude may use `head -100` for nested files)
5. **Table of contents**: Reference files over 100 lines should have a TOC at the top

**Example of good context clues:**

```markdown
## Advanced Features

**For form filling workflows**: See [FORMS.md](FORMS.md) - load when user mentions forms, fillable PDFs
**For API reference**: See [REFERENCE.md](REFERENCE.md) - load for method signatures, parameters
**For troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - load on errors, failures
```

**Query docs-management for complete guidance:**

```text
Find documentation about progressive disclosure patterns for skills
```

### Skill Composition Pattern

Skills can invoke other skills for modular architectures.

**Example:** "Find and use the current-date skill to get today's date"

**Query docs-management for composition details:**

```text
Find documentation about skill composition and skills invoking other skills
```

### Tool Restriction Pattern

Use `allowed-tools` to limit Claude's capabilities within a skill (read-only analysis, audit workflows, safety-critical operations).

**Example:**

```yaml
---
name: readonly-analyzer
description: Analyze code without modifications
allowed-tools: Read, Grep, Glob
---
```

**Query docs-management for complete specification:**

```text
Find documentation about allowed-tools configuration and tool restrictions
```

## Troubleshooting Activation

**Skill doesn't activate:**

1. Check description specificity (add trigger keywords)
2. Verify YAML syntax (opening/closing `---`, valid YAML)
3. Confirm file paths (correct directory structure)
4. Test with direct invocation ("Use the [skill-name] skill to...")
5. Check for conflicts (make descriptions distinct)

**Query docs-management for troubleshooting:**

```text
Find documentation about skill activation issues and troubleshooting
```

## Skill Template

**Location:** `assets/skill-template/`

**5 Structural Patterns:**

1. **Workflow-Based** - Sequential processes
2. **Task-Based** - Collections of operations
3. **Reference-Based** - Guidelines and standards
4. **Capabilities-Based** - Integrated features
5. **Validation Feedback Loop** - Operations requiring correctness

**Usage:**

```bash
cp -r .claude/skills/skill-development/assets/skill-template .claude/skills/[new-skill-name]
```

## Best Practices Summary

**DO:**

- ✅ Query `docs-management` skill for all official documentation
- ✅ Use the skill template for new skills
- ✅ Write specific descriptions with trigger keywords
- ✅ Test activation with varied phrasings
- ✅ Use progressive disclosure (SKILL.md → references/)
- ✅ Follow naming conventions (gerund or noun, avoid agent nouns)

**DON'T:**

- ❌ Duplicate official documentation
- ❌ Create mega-skills that do too much
- ❌ Use vague descriptions
- ❌ Skip activation testing
- ❌ Use uppercase or special characters in skill names

**For complete best practices:**

Query `docs-management`:

```text
Find the complete skill authoring best practices documentation
```

## References

**Detailed workflows:**

- [Creating Skills Workflow](references/workflows/creating-skills-workflow.md)
- [Validating Skills Workflow](references/workflows/validating-skills-workflow.md)
- [Testing Skills Workflow](references/workflows/testing-skills-workflow.md)
- [Distributing Skills Workflow](references/workflows/distributing-skills-workflow.md)

**Quality and auditing:**

- [Skill Audit Guide](references/quality/skill-audit-guide.md)

**Metadata and conventions:**

- [Search Keywords Registry](references/metadata/search-keywords.md)
- [Common Use Cases](references/metadata/common-use-cases.md)
- [Naming Conventions](references/metadata/naming-conventions.md)
- [YAML Frontmatter Reference](references/metadata/yaml-frontmatter-reference.md)

**Pattern examples:**

- [Progressive Disclosure Examples](references/patterns/progressive-disclosure-examples.md)
- [Skill Composition Patterns](references/patterns/skill-composition-patterns.md)
- [Tool Restriction Patterns](references/patterns/tool-restriction-patterns.md)

**Template:**

- [Skill Template](assets/skill-template/SKILL.md)

## Test Scenarios

### Scenario 1: Creating a new skill

**Query:** "I need to create a new skill for processing Excel files"

**Expected:** Skill activates, guides to template, provides creation workflow

**Success:** User gets template location, knows to query docs-management, understands structural patterns

### Scenario 2: Validating an existing skill

**Query:** "Validate this skill's YAML frontmatter and structure"

**Expected:** Skill activates, provides validation workflow, directs to docs-management

**Success:** User validates YAML, checks naming, verifies structure, tests activation

### Scenario 3: Troubleshooting activation

**Query:** "My skill isn't activating when I expect it to"

**Expected:** Skill activates, provides diagnostic steps, suggests description improvements

**Success:** User identifies issue, improves description, tests successfully

## Related Skills

- **docs-management** - Official documentation access (all documentation queries delegate here)
- **current-date** - Get current UTC date for version history and audit timestamps
- **markdown-linting** - Validate SKILL.md formatting and structure

## Version History

- v1.0.4 (2025-11-25): Enhancements - Added Related Skills section, enhanced reference files, improved progressive disclosure
- v1.0.3 (2025-11-25): Comprehensive audit - Replaced hardcoded versions with generic names, added tool verification
- v1.0.2 (2025-11-24): Decoupling improvements - Replaced doc_ids with natural language queries
- v1.0.1 (2025-11-17): Post-audit improvements - Added Reference Loading Guide, fixed links
- v1.0.0 (2025-11-17): Initial release - Delegation-first meta-skill with zero duplication

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
