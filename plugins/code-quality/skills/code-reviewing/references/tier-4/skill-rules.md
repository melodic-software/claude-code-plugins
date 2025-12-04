# Skill File Rules

Validation rules for `.claude/skills/**` files (SKILL.md, YAML frontmatter, reference files).

## SKILL.md Required Structure

- [ ] **SKILL.md is mandatory entry point for every skill**
  - Located at `.claude/skills/{skill-name}/SKILL.md`
  - Contains YAML frontmatter + markdown content
  - Missing SKILL.md means skill is non-functional
  - Rationale: Standardized skill interface

- [ ] **Required sections in SKILL.md**
  - Overview (what skill does)
  - When to Use (activation patterns)
  - Progressive disclosure sections (tier-based loading)
  - Last Verified section (version/date tracking)
  - Rationale: Consistency, discoverability

## YAML Frontmatter Requirements

- [ ] **Frontmatter must be valid YAML**
  - Starts with `---` on first line
  - Ends with `---` on its own line
  - Valid YAML syntax (no tabs, proper indentation)
  - Rationale: Parsing failures break skill loading

- [ ] **Required frontmatter fields**
  - `name`: Skill name (matches directory name)
  - `description`: Brief purpose summary (1-2 sentences)
  - Rationale: Minimum metadata for skill discovery

- [ ] **allowed-tools field controls tool access**
  - Lists specific tools skill can use (e.g., `[Read, Grep, Glob]`)
  - `*` means all tools (use sparingly)
  - Missing field defaults to all tools
  - Rationale: Least privilege, explicit permissions

**Detection Pattern:**

```yaml
---
name: code-reviewing
description: Performs systematic code review with best practices
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
---
```

## Progressive Disclosure Pattern

- [ ] **Use tiered information loading**
  - Start with essential guidance (always visible)
  - Load detailed references only when needed
  - Use `@` imports or tier markers to organize
  - Rationale: Token efficiency, context management

- [ ] **Reference files under references/ subdirectory**
  - Structure: `.claude/skills/{skill}/references/{category}/{file}.md`
  - Examples: `references/tier-2/backend-checks.md`
  - Keeps SKILL.md focused, references optional
  - Rationale: Modular organization, selective loading

## Skill Encapsulation

- [ ] **Never expose internal file paths externally**
  - Commands, other skills, docs use skill NAME only
  - Internal structure (scripts, references) is implementation detail
  - Example: Say "invoke code-reviewing skill", not "read .claude/skills/code-reviewing/references/checklist.md"
  - Rationale: Encapsulation, refactoring flexibility

- [ ] **Skill controls its own tool usage**
  - External callers describe intent in natural language
  - Skill interprets intent and uses appropriate tools
  - Don't dictate "use Grep then Read" from outside
  - Rationale: Separation of concerns, autonomy

**Detection Pattern:**

```markdown
<!-- BAD: Exposing internal paths -->
To run code review, read `.claude/skills/code-reviewing/references/checklist.md`

<!-- GOOD: Using skill name -->
To run code review, invoke the code-reviewing skill
```

## Token Budget Awareness

- [ ] **Skills must be token-efficient**
  - SKILL.md should be <5000 tokens (ideally <3000)
  - Reference files should be focused, single-purpose
  - Use progressive disclosure to defer non-essential content
  - Rationale: Context window limits, performance

- [ ] **Estimate token costs in documentation**
  - Note token counts for reference files in comments
  - Example: `<!-- ~600 tokens -->`
  - Helps users understand context consumption
  - Rationale: Transparency, budget planning

## Reference File Organization

- [ ] **Group references by category or tier**
  - `references/tier-1/` - Core universal checks
  - `references/tier-2/` - Domain-specific checks
  - `references/tier-3/` - Advanced patterns
  - `references/tier-4/` - Project-specific rules
  - Rationale: Hierarchical loading, discoverability

- [ ] **Reference files follow consistent format**
  - Checklist items using `- [ ]` format
  - Detection patterns showing good/bad examples
  - Brief rationale for each rule
  - Rationale: Consistency, readability

## Skill Composition

- [ ] **Skills may invoke other skills**
  - Use natural language delegation (e.g., "invoke official-docs skill")
  - Never bypass skills to call their internal components
  - Respect skill encapsulation boundaries
  - Rationale: Modularity, reuse, maintainability

## Reference File Validation

- [ ] **All referenced files verified to exist**
  - SKILL.md tables reference files (references/, agents/, etc.)
  - Use Glob to verify ALL referenced files exist
  - Do NOT conclude files missing based on partial reads
  - Command: `Glob pattern="skill/references/**/*.md"`
  - Rationale: Prevents false positives about missing files

- [ ] **Cross-reference with staged files**
  - For new skills: All referenced files should appear in git status
  - Staged files with `A` (added) status are new files
  - Verify count matches: 8 references in table = 8 files in Glob results
  - Rationale: Consistency between documentation and implementation

- [ ] **Reference links use valid paths**
  - Markdown links: `[text](path/to/file.md)`
  - Verify path exists with Glob before reporting missing
  - Rationale: Broken links degrade user experience

## Version Tracking

- [ ] **Last Verified section tracks currency**
  - Date: When skill was last validated
  - Tool versions: Which versions were tested
  - Model: Which Claude model performed verification
  - Rationale: Staleness detection, maintenance scheduling

**Detection Pattern:**

```markdown
## Last Verified

**Date:** 2025-11-28
**Model:** Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)
**Tool Versions Tested:**
- markdownlint-cli2: 0.15.0+
- ESLint: 9.0.0+
```

## Naming Conventions

- [ ] **Skill directory names are kebab-case**
  - Example: `code-reviewing`, `official-docs`, `git-commit`
  - Match YAML `name` field exactly
  - Rationale: Consistency, URL-friendly

- [ ] **Reference file names are descriptive**
  - Example: `backend-checks.md`, `security-patterns.md`
  - Avoid generic names like `rules.md`, `stuff.md`
  - Rationale: Discoverability, clarity

---

**Tier:** 4 (CLAUDE.md-specific)
**Applies To:** `.claude/skills/**` files
**Last Updated:** 2025-11-28
