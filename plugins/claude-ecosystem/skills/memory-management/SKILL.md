---
name: memory-management
description: Meta-skill for Claude Code memory system (CLAUDE.md, static memory). Provides stable principles, keyword registry for documentation lookups, and navigation guidance. Use when working with CLAUDE.md files, memory hierarchy, import syntax, progressive disclosure patterns, memory organization, or best practices for static memory. Delegates to docs-management skill for current implementation details. Keywords: CLAUDE.md, static memory, memory hierarchy, import syntax, progressive disclosure, memory organization, enterprise project user memory.
allowed-tools: Read, Glob, Grep, Skill
---

# Memory Meta

## 🚨 MANDATORY: Invoke docs-management First

> **STOP - Before providing ANY response about Claude Code memory (CLAUDE.md):**
>
> 1. **INVOKE** `docs-management` skill
> 2. **QUERY** using keywords: CLAUDE.md, static memory, memory hierarchy, import syntax, or related topics
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded
>
> **Skipping this step results in outdated or incorrect information.**

### Verification Checkpoint

Before responding, verify:

- [ ] Did I invoke docs-management skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

If ANY checkbox is unchecked, STOP and invoke docs-management first.

## Meta-skill for Claude Code memory system - 100% driven by official documentation

> **Zero Duplication Policy**
>
> This skill contains ZERO duplicated content from official documentation. ALL implementation details delegate to the `docs-management` skill using natural language queries. This skill provides stable principles and navigation that won't change, while docs-management provides current official guidance.

## Overview

This meta-skill provides stable principles, keyword registries, and patterns for working with Claude Code's memory system (CLAUDE.md files, static memory). It does NOT duplicate official documentation - instead, it teaches you how to efficiently query the `docs-management` skill for any memory-related information you need.

**What this skill provides:**

- Stable principles that won't change (timeless guidance)
- Keyword registry for efficient documentation lookups
- Common organization patterns
- Quick decision trees for navigation
- Troubleshooting guidance

**What this skill delegates to docs-management:**

- Current import syntax specifications
- Exact file locations and paths
- Version-specific behaviors
- Implementation details that may evolve
- Complete best practices documentation

## When to Use This Skill

This skill should be used when:

- **Working with CLAUDE.md files** - Creating, editing, or organizing memory
- **Memory hierarchy questions** - Understanding enterprise/project/user/local precedence
- **Import syntax questions** - How to import files, @ syntax, recursive lookup
- **Progressive disclosure patterns** - Organizing always-loaded vs on-demand content
- **Memory organization** - Hub-and-spoke, token budgets, cross-references
- **Best practices lookup** - Efficient queries to find official guidance

## Stable Principles (Won't Change)

These principles are fundamental to how LLMs and memory systems work. They won't change even as Claude Code's implementation evolves.

### 1. Progressive Disclosure

**Principle:** Load context on-demand, not everything upfront.

**Why stable:** Context windows are finite resources. This is a fundamental LLM constraint that won't change.

**Application:**

- Always-loaded content should be minimal and high-signal
- Detailed content loads only when needed
- Hub files link to detailed references

### 2. Strategic Emphasis

**Principle:** Use emphasis keywords (CRITICAL, NEVER, MUST, IMPORTANT) strategically for must-follow rules.

**Why stable:** Human communication patterns for priority signaling are universal.

**Application:**

- Reserve emphasis for truly critical rules
- Don't overuse (dilutes effectiveness)
- Use consistently across your memory files

### 3. Specificity Over Vagueness

**Principle:** "Use 2-space indent" beats "format code properly"

**Why stable:** Specific instructions are universally more actionable than vague ones.

**Application:**

- Concrete examples over abstract guidance
- Exact commands over general directions
- Measurable criteria over subjective standards

### 4. Structure Aids Parsing

**Principle:** Bullets, headings, and clear organization improve comprehension.

**Why stable:** Both humans and LLMs process structured content more effectively.

**Application:**

- Use markdown headings consistently
- Bullet points for lists of items
- Tables for structured comparisons
- Code blocks for commands/examples

### 5. Hierarchy/Layering

**Principle:** Configuration layers override each other (enterprise → project → user → local).

**Why stable:** Standard configuration pattern used across all software systems.

**Application:**

- Higher levels set defaults
- Lower levels can override
- Understand which level your changes belong to

### 6. Token Efficiency

**Principle:** Context is finite - be efficient with tokens.

**Why stable:** LLM context windows have limits. Even as they grow, efficiency matters.

**Application:**

- Remove redundant content
- Link instead of duplicate
- Use progressive disclosure
- Monitor token budgets

**Detailed explanations:** See [Stable Principles Reference](references/stable-principles.md)

## Quick Decision Tree

**What do you want to do?**

1. **Create a new CLAUDE.md file** → Query docs-management: "Find documentation about creating CLAUDE.md files and /init command"

2. **Organize memory for a project** → See [Common Patterns](references/common-patterns.md)

3. **Understand import syntax** → Query docs-management: "Find documentation about CLAUDE.md import syntax and @ references"

4. **Set up memory hierarchy** → Query docs-management: "Find documentation about memory hierarchy enterprise project user"

5. **Optimize token usage** → See [Stable Principles](#stable-principles-wont-change) + [Common Patterns](references/common-patterns.md)

6. **Fix memory not loading** → See [Troubleshooting](#troubleshooting)

7. **Find official best practices** → See [Keyword Registry](references/keyword-registry.md) for efficient queries

## Keyword Registry for docs-management

Use these keywords when querying the `docs-management` skill for memory-related documentation:

### Core Memory System

**Keywords:** `CLAUDE.md`, `static memory`, `memory hierarchy`, `memory system`

**Example query:**

```text
Find documentation about CLAUDE.md static memory system and memory hierarchy
```

### Import Syntax

**Keywords:** `import syntax`, `@ references`, `recursive lookup`, `file imports`

**Example query:**

```text
Find documentation about CLAUDE.md import syntax and @ file references
```

### Memory Commands

**Keywords:** `/init command`, `/memory command`, `# shortcut`, `memory commands`

**Example query:**

```text
Find documentation about /init and /memory commands for CLAUDE.md
```

### Best Practices

**Keywords:** `memory best practices`, `CLAUDE.md tuning`, `memory organization`

**Example query:**

```text
Find documentation about CLAUDE.md best practices and memory tuning
```

### Agent SDK Integration

**Keywords:** `settingSources`, `memory API`, `Agent SDK memory`

**Example query:**

```text
Find documentation about Agent SDK settingSources and memory integration
```

**Complete keyword registry:** See [Keyword Registry Reference](references/keyword-registry.md)

## Common Patterns

### Hub-and-Spoke Organization

**Pattern:** Central hub file (CLAUDE.md) links to detailed reference files.

```text
CLAUDE.md (hub)
├─ Quick Reference (essential, always loaded)
├─ Core principles (brief)
└─ Links to detailed docs
    ├─→ .claude/memory/architecture.md
    ├─→ .claude/memory/workflows.md
    └─→ .claude/memory/testing.md
```

**Benefits:**

- Hub stays small (token efficient)
- Details load on-demand
- Single entry point
- Easy navigation

### Always-Loaded vs Context-Dependent

**Pattern:** Separate critical content from detailed content.

**Always-loaded (@-prefixed imports):**

- Core principles that apply to every task
- Critical rules that must never be violated
- Quick reference for common operations
- ~10-15k tokens maximum recommended

**Context-dependent (loaded on-demand):**

- Detailed guides for specific topics
- Reference documentation
- Examples and templates
- Can be larger since loaded selectively

### Token Budget Strategy

**Pattern:** Allocate tokens intentionally across memory tiers.

| Tier | Target Budget | Content Type |
| ------ | --------------- | -------------- |
| Always-loaded | ~10-15k tokens | Core principles, critical rules |
| On-demand | ~30-50k tokens | Detailed guides, references |
| External (skills) | Unlimited | Delegated documentation |

**Detailed patterns:** See [Common Patterns Reference](references/common-patterns.md)

## Troubleshooting

### Memory Not Loading

**Symptoms:** CLAUDE.md content doesn't appear in context

**Diagnostic steps:**

1. **Check file location:**
   - Project: `./CLAUDE.md` at repo root
   - User: `~/.claude/CLAUDE.md`

2. **Check import syntax:**
   - Valid: `@path/to/file.md`
   - Invalid: `@path/to/file` (missing extension)
   - Invalid: Inside code blocks (imports not processed)

3. **Check file exists:**
   - Imported files must exist at specified paths
   - Relative paths resolve from importing file's location

**Query docs-management for current troubleshooting:**

```text
Find documentation about CLAUDE.md troubleshooting and memory loading issues
```

### Import Syntax Issues

**Common mistakes:**

- Missing `@` prefix for always-loaded imports
- Using imports inside code blocks (won't be processed)
- Circular imports (A imports B imports A)
- Exceeding max import depth

**Query docs-management for syntax specification:**

```text
Find documentation about CLAUDE.md import syntax requirements and limitations
```

### Hierarchy Conflicts

**Symptoms:** Unexpected behavior due to conflicting instructions

**Resolution:**

1. Identify which level each instruction comes from
2. Higher levels (enterprise) override lower levels (user)
3. Within same level, later content may override earlier
4. Use specific instructions to override general ones

**Query docs-management for hierarchy details:**

```text
Find documentation about memory hierarchy precedence and conflict resolution
```

## Reference Loading Guide

**All references in this skill are conditional load** - they are loaded only when needed.

### When to Load Each Reference

- **stable-principles.md** → When you need detailed explanation of why principles are stable
- **keyword-registry.md** → When you need comprehensive keyword list for docs-management queries
- **common-patterns.md** → When implementing memory organization patterns

### Progressive Disclosure Strategy

#### Layer 1: Always in Context

- SKILL.md (this file) - Navigation hub, quick reference

#### Layer 2: Load on Demand

- Reference files when specific topic needed

#### Layer 3: External Delegation

- Official documentation via `docs-management` skill (always current)

## Related Skills

**Skills that work well with memory-management:**

- **docs-management** - Official documentation access (memory-management delegates all documentation queries here)
- **skill-development** - If you're creating skills that use memory patterns
- **current-date** - For Last Updated timestamps in memory files

## Best Practices Summary

**DO:**

- Query `docs-management` for all official documentation
- Use stable principles as foundation (they won't change)
- Apply progressive disclosure (always-loaded vs on-demand)
- Keep hub files small and focused
- Use keyword registry for efficient lookups
- Monitor token budgets

**DON'T:**

- Duplicate official documentation
- Put everything in always-loaded imports
- Use vague instructions ("do things properly")
- Ignore token budgets
- Skip verification of import syntax

## Auditing Memory Files

This skill provides the validation criteria used by the `memory-auditor` agent for formal audits.

### Audit Resources

| Resource | Location | Purpose |
| -------- | -------- | ------- |
| Audit Framework | `references/audit-framework.md` | Query guides and scoring criteria |

### Scoring Categories

| Category | Points | Key Criteria |
| -------- | ------ | ------------ |
| Structure | 25 | Valid markdown, proper sections |
| Import Syntax | 25 | Correct @path syntax, files exist |
| Hierarchy Compliance | 20 | Correct level (enterprise/project/user) |
| Content Organization | 20 | Progressive disclosure, appropriate size |
| No Anti-Patterns | 10 | No circular imports, excessive nesting |

**Thresholds:** 85+ = PASS, 70-84 = PASS WITH WARNINGS, <70 = FAIL

### Related Agent

The `memory-auditor` agent (Haiku model) performs formal audits using this skill:

- Auto-loads this skill via `skills: memory-management`
- Uses audit framework and docs-management for rules
- Generates structured audit reports
- Invoked by `/audit-memory` command

## References

**Reference files:**

- [Stable Principles](references/stable-principles.md) - Detailed explanation of timeless principles
- [Keyword Registry](references/keyword-registry.md) - Complete keyword list for docs-management queries
- [Common Patterns](references/common-patterns.md) - Memory organization patterns and examples
- [Audit Framework](references/audit-framework.md) - Audit scoring and query guides

## Version History

- v1.0.0 (2025-11-26): Initial release - Delegation-first meta-skill with stable principles, keyword registry, and common patterns

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
