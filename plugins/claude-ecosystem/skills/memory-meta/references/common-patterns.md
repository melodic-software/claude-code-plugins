# Common Patterns Reference

## Overview

This document provides common patterns for organizing Claude Code memory effectively. These patterns are implementation-focused, showing how to apply the stable principles in practice.

## Hub-and-Spoke Organization

### Pattern Description

A central hub file (CLAUDE.md) links to detailed reference files, creating a navigable tree structure.

```text
CLAUDE.md (hub)
├── Quick Reference (always in context)
├── Core Principles (brief summaries)
└── Links to detailed docs
    ├── .claude/memory/architecture.md
    ├── .claude/memory/workflows.md
    ├── .claude/memory/testing.md
    └── .claude/memory/guidelines.md
```

### Benefits

- **Token efficiency**: Hub stays small, details load on-demand
- **Navigation**: Single entry point for all memory
- **Maintainability**: Detailed content isolated in focused files
- **Scalability**: Add new spokes without bloating hub

### Implementation Example

**Hub file (CLAUDE.md):**

```markdown
# Project Memory

## Quick Reference

- Build: `npm run build`
- Test: `npm test`
- Deploy: `npm run deploy`

## Core Principles

See @.claude/memory/principles.md for detailed principles.

## Architecture

See @.claude/memory/architecture.md for system design.

## Workflows

See @.claude/memory/workflows.md for common workflows.
```

**Spoke file (.claude/memory/architecture.md):**

```markdown
# Architecture

## System Design

[Detailed architecture documentation...]

## Components

[Component descriptions...]

## Patterns

[Design patterns used...]
```

### When to Use

- Projects with more than ~5k tokens of memory content
- Multiple distinct topic areas
- Team projects where different roles need different details
- Growing documentation that will expand over time

## Always-Loaded vs Context-Dependent

Separate critical content (always loaded) from detailed content (loaded when needed).

### Always-Loaded Content

Content that applies to every task. Use `@` prefix in CLAUDE.md.

**Characteristics:**

- Core principles that never change
- Critical rules (security, safety)
- Quick reference for common operations
- Project identity and conventions

**Example:**

```markdown
## Always-Loaded Content

The following is imported with @-prefix and always in context:

@.claude/memory/core-principles.md (~1k tokens)
@.claude/memory/critical-rules.md (~500 tokens)
@.claude/memory/quick-reference.md (~500 tokens)

Total always-loaded: ~2k tokens
```

### Context-Dependent Content

Content loaded only when relevant. Use backticks without @ prefix.

**Characteristics:**

- Detailed guides for specific topics
- Reference documentation
- Examples and templates
- Historical or archival information

**Example:**

```markdown
## Context-Dependent Content

The following loads on-demand when needed:

`.claude/memory/testing-guide.md` - Load when testing
`.claude/memory/deployment-guide.md` - Load when deploying
`.claude/memory/troubleshooting.md` - Load when debugging
```

### Decision Framework

| Question | Yes → | No → |
| -------- | ----- | ---- |
| Does this apply to EVERY task? | Always-loaded | Context-dependent |
| Is violation catastrophic? | Always-loaded | Context-dependent |
| Is this referenced frequently? | Always-loaded | Context-dependent |
| Is this detailed reference? | Context-dependent | Always-loaded |

## Token Budget Management

Allocate tokens intentionally across memory tiers with explicit budgets.

### Recommended Budgets

```text
Total practical budget: ~50-60k tokens

Tier 1: Always-loaded (~10-15k, 20-25%)
├── CLAUDE.md hub: 3-5k tokens
├── Core principles: 2-3k tokens
├── Critical rules: 1-2k tokens
└── Quick reference: 2-3k tokens

Tier 2: On-demand (~30-40k, 60-70%)
├── Detailed guides: 10-15k tokens
├── Reference docs: 10-15k tokens
└── Examples/templates: 5-10k tokens

Tier 3: Reserved (~5-10k, 10-15%)
└── Buffer for conversation context
```

### Tracking Token Usage

**In CLAUDE.md, document token estimates:**

```markdown
## Memory Token Budget

**Always-Loaded (~12k tokens):**
- architectural-principles.md (~700 tokens)
- quality-standards.md (~1,800 tokens)
- operational-rules.md (~6,900 tokens)
- command-skill-protocol.md (~2,400 tokens)

**Context-Dependent (~38k tokens):**
- architecture.md (~3,700 tokens)
- workflows.md (~2,900 tokens)
- testing-principles.md (~11,400 tokens)
- [etc.]

**Total: ~50k tokens**
```

### Estimation Rule

~1.3 tokens per word for English text. Quick estimate:

- 100 words ≈ 130 tokens
- 1,000 words ≈ 1,300 tokens
- 10,000 words ≈ 13,000 tokens

## Cross-Reference Conventions

Consistent conventions for referencing between memory files.

### Reference Syntax

**Always-loaded import (processed at load time):**

```markdown
@.claude/memory/file.md
```

**On-demand reference (link for navigation):**

```markdown
See `.claude/memory/file.md` for details.
```

**Anchor references (specific sections):**

```markdown
See @.claude/memory/file.md#section-name
```

### Naming Conventions

**File names:**

- Use kebab-case: `testing-principles.md`
- Descriptive names: `architectural-principles.md` not `arch.md`
- No numbered prefixes: `workflows.md` not `01-workflows.md`

**Section anchors:**

- Use heading text converted to lowercase with hyphens
- `## Quick Reference` → `#quick-reference`

### Cross-Reference Best Practices

**Do:**

- Use relative paths from CLAUDE.md location
- Include file extension (.md)
- Reference specific sections when appropriate
- Keep references up-to-date

**Don't:**

- Use absolute paths
- Omit file extensions
- Create circular references
- Reference non-existent files

## Layered Content Strategy

Organize content in progressive layers, from overview to detail.

### Three-Layer Model

#### Layer 1: Overview (always visible)

- What it is (1-2 sentences)
- When to use it
- Quick start command

#### Layer 2: Core Details (in same file)

- Key concepts
- Main workflows
- Important configurations

#### Layer 3: Deep Reference (separate files)

- Comprehensive documentation
- Edge cases
- Historical context
- Examples and templates

### Example Implementation

**CLAUDE.md (Layer 1):**

```markdown
## Testing

Run tests: `npm test`

See @.claude/memory/testing.md for testing guidelines.
```

**testing.md (Layer 2):**

```markdown
# Testing Guidelines

## Quick Reference

- Unit tests: `npm test`
- Integration: `npm run test:integration`
- Coverage: `npm run test:coverage`

## Core Concepts

[Key testing concepts for this project...]

## Detailed Reference

See `.claude/memory/testing-advanced.md` for advanced topics.
```

**testing-advanced.md (Layer 3):**

```markdown
# Advanced Testing

[Comprehensive testing documentation...]
```

## Summary

| Pattern | Use When | Key Benefit |
| ------- | -------- | ----------- |
| Hub-and-Spoke | Multiple topic areas | Navigation and scalability |
| Always/On-Demand | Mixed critical and reference content | Token efficiency |
| Token Budgets | Large memory systems | Predictable performance |
| Cross-References | Multi-file memory | Consistent navigation |
| Layered Content | Complex topics | Progressive disclosure |

## Related

- [SKILL.md](../SKILL.md) - Main hub with quick reference
- [Stable Principles](stable-principles.md) - Underlying principles
- [Keyword Registry](keyword-registry.md) - For official docs queries

---

**Last Updated:** 2025-11-26
