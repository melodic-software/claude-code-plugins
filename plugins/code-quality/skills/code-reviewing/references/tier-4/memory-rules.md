# Memory File Rules

Validation rules for `.claude/memory/**` files (static memory system for Claude Code).

## Memory File Hierarchy

- [ ] **Memory files organized by scope**
  - Enterprise: `.claude/enterprise-memory/` (organization-wide)
  - Project: `.claude/memory/` (repository-specific)
  - User: `~/.config/claude/memory/` (personal across projects)
  - Local: `.claude/local-memory/` (machine-specific, gitignored)
  - Rationale: Hierarchical context, appropriate sharing

- [ ] **Project memory is version-controlled**
  - `.claude/memory/` files committed to repo
  - Shared across team, consistent project context
  - Example: `architectural-principles.md`, `quality-standards.md`
  - Rationale: Team alignment, consistent guidance

## Import Syntax

- [ ] **Use @ syntax for memory imports in CLAUDE.md**
  - Pattern: `@.claude/memory/{file}.md`
  - Example: `@.claude/memory/operational-rules.md`
  - Enables progressive disclosure and context management
  - Rationale: Token efficiency, on-demand loading

- [ ] **Memory imports load on-demand**
  - Not all memory files loaded at session start
  - Claude loads when relevant to current task
  - Import syntax makes files discoverable
  - Rationale: Context window optimization

**Detection Pattern:**

```markdown
<!-- CLAUDE.md structure -->
## Always Loaded (Core Principles)
- **Operational Rules** @.claude/memory/operational-rules.md (~3,500 tokens)

## Context-Dependent (Load When Needed)
- **Path Conventions** `.claude/memory/path-conventions.md` (~2,800 tokens)
```

## Token Budget Awareness

- [ ] **Memory files should be focused and bounded**
  - Individual files: <5000 tokens ideal, <10000 max
  - Always-loaded set: Keep under 15000 tokens total
  - Context-dependent files: Load selectively
  - Rationale: Context window limits, performance

- [ ] **Document token counts in CLAUDE.md**
  - Pattern: `(~3,500 tokens)` next to import
  - Helps track total context consumption
  - Update when files grow significantly
  - Rationale: Budget transparency, maintenance planning

## Context-Dependent Loading

- [ ] **Mark files as always-loaded or context-dependent**
  - Always-loaded: Core principles needed in every session
  - Context-dependent: Load when specific topic is relevant
  - Include keywords to aid discovery
  - Rationale: Efficient context management

- [ ] **Provide keywords for context-dependent files**
  - Example: "Keywords: path resolution, script execution, path doubling"
  - Helps Claude determine when to load file
  - List in CLAUDE.md next to import reference
  - Rationale: Discoverability, appropriate loading

**Detection Pattern:**

```markdown
- **Path Conventions** `.claude/memory/path-conventions.md` (~2,800 tokens)
  Load when working with paths, scripts, or debugging path doubling issues.
  Keywords: path resolution, absolute paths, path doubling, script execution
```

## Hub-and-Spoke Organization

- [ ] **Use hub files to organize related memory**
  - Hub: Central file with overview + links
  - Spokes: Detailed topic-specific files
  - Example: `claude-code-ecosystem.md` (hub) links to meta-skills
  - Rationale: Progressive disclosure, navigation

- [ ] **Hub files avoid content duplication**
  - Hubs provide structure and navigation
  - Detailed content lives in spoke files only
  - Links from hub to spokes, not copy-paste
  - Rationale: Single source of truth, DRY

## Last Updated Dates

- [ ] **All memory files include Last Updated date**
  - Format: `**Last Updated:** YYYY-MM-DD`
  - Placed at end of file
  - Tracks currency and maintenance
  - Rationale: Staleness detection

**Detection Pattern:**

```markdown
---
**Last Updated:** 2025-11-28
```

## Memory File Naming

- [ ] **Memory file names are descriptive kebab-case**
  - Example: `operational-rules.md`, `agent-usage-patterns.md`
  - Avoid generic names like `notes.md`, `misc.md`
  - Match content scope precisely
  - Rationale: Discoverability, clarity

## Cross-References Between Memory Files

- [ ] **Memory files may reference each other**
  - Use relative paths: `.claude/memory/other-file.md`
  - Or use @ syntax for imports
  - Avoid circular dependencies
  - Rationale: Modularity, reuse

## Memory File Content Standards

- [ ] **Memory files follow documentation quality standards**
  - Clear sections and headings
  - Actionable guidance (not vague principles)
  - Examples and detection patterns where helpful
  - Rationale: Usability, Claude can apply guidance

- [ ] **Memory files are AI-optimized**
  - Direct, declarative sentences
  - Explicit steps and imperative verbs
  - Predictable structure for LLM parsing
  - Rationale: Claude can reliably extract and apply

## Scope and Purpose Clarity

- [ ] **Each memory file has clear, focused scope**
  - One topic per file (e.g., paths, agents, testing)
  - Avoid mixing unrelated concerns in one file
  - Purpose stated in first paragraph
  - Rationale: Clarity, maintainability

---

**Tier:** 4 (CLAUDE.md-specific)
**Applies To:** `.claude/memory/**` files
**Last Updated:** 2025-11-28
