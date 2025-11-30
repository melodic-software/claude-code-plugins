# Stable Principles Reference

## Overview

This document provides detailed explanations of the six stable principles for Claude Code memory systems. These principles are **timeless** - they won't change even as Claude Code's implementation evolves because they're rooted in fundamental constraints of LLMs and good software design.

## Why These Principles Are Stable

Each principle below is stable because it's based on:

- **Fundamental LLM constraints** (context windows, token processing)
- **Universal communication patterns** (how humans convey priority)
- **Software engineering fundamentals** (configuration patterns, efficiency)

These foundations don't change even as tools evolve.

## The Six Stable Principles

### 1. Progressive Disclosure

> Load context on-demand, not everything upfront.

#### Stability Rationale

Context windows are a fundamental constraint of LLM architecture. Even as context windows grow larger, they remain finite. Loading everything upfront:

- Wastes tokens on content that may not be needed
- Dilutes important information with less relevant content
- Increases latency and cost

Progressive disclosure is how we manage finite resources efficiently - a timeless optimization pattern.

#### Application

**Structure memory in layers:**

```text
Layer 1: Always loaded (~10-15k tokens)
├─ Critical rules that apply to every task
├─ Core principles and project identity
└─ Quick reference for common operations

Layer 2: Loaded on demand
├─ Detailed guides for specific topics
├─ Reference documentation
└─ Examples and templates

Layer 3: External delegation
└─ Official docs via skills (unlimited, always current)
```

**Decision criteria for placement:**

- "Does this apply to EVERY task?" → Always loaded
- "Does this apply to SOME tasks?" → On demand
- "Is this official documentation?" → Delegate to skill

### 2. Strategic Emphasis

> Use emphasis keywords (CRITICAL, NEVER, MUST, IMPORTANT) strategically for must-follow rules.

#### Stability Rationale (Emphasis)

Priority signaling is a fundamental human communication pattern. Words like "CRITICAL" and "NEVER" have carried weight for centuries and will continue to do so. LLMs are trained on human text and respond to these signals.

#### Application (Emphasis)

**Emphasis hierarchy:**

| Keyword | Use When | Example |
| ------- | -------- | ------- |
| CRITICAL | Violation causes system failure | "CRITICAL: Never commit secrets" |
| NEVER | Action must be avoided always | "NEVER use eval() on user input" |
| MUST | Action is required, no exceptions | "You MUST validate input" |
| IMPORTANT | Significant but not catastrophic | "IMPORTANT: Follow naming conventions" |

**Anti-patterns to avoid:**

- Overusing emphasis (dilutes effectiveness)
- Using emphasis for preferences (reserve for requirements)
- Inconsistent emphasis (pick patterns and stick to them)

**Effective pattern:**

```markdown
**CRITICAL:** Never expose API keys in logs or responses.

**IMPORTANT:** Follow the project naming convention (kebab-case for files).
```

### 3. Specificity Over Vagueness

> "Use 2-space indent" beats "format code properly"

#### Stability Rationale (Specificity)

Specific instructions are universally more actionable than vague ones. This is true for humans, LLMs, and any instruction-following system. Vague instructions require interpretation; specific ones require execution.

#### Application (Specificity)

**Transform vague to specific:**

| Vague | Specific |
| ----- | -------- |
| "Format code properly" | "Use 2-space indentation, 80 char line limit" |
| "Write good tests" | "Each test has Arrange/Act/Assert sections" |
| "Follow best practices" | "Use TypeScript strict mode, no any types" |
| "Be secure" | "Validate all user input, escape HTML output" |

**Specificity checklist:**

- Can this instruction be followed without interpretation?
- Would two people following this produce similar results?
- Is there a measurable or verifiable outcome?

If any answer is "no," make it more specific.

### 4. Structure Aids Parsing

> Bullets, headings, and clear organization improve comprehension.

#### Stability Rationale (Structure)

Both humans and LLMs process structured content more effectively than unstructured prose. This is fundamental to how information processing works:

- Headings create navigable hierarchy
- Bullets enable scanning and enumeration
- Tables present comparisons clearly
- Code blocks distinguish executable content

#### Application (Structure)

**Use appropriate structures:**

| Content Type | Best Structure |
| ------------ | -------------- |
| Sequential steps | Numbered list |
| Unordered items | Bullet list |
| Comparisons | Table |
| Commands/code | Code block |
| Sections | Headings (H1-H4) |

**Structural patterns for memory files:**

```markdown
## Section Name

Brief introduction (1-2 sentences).

**Key point 1:** Explanation

**Key point 2:** Explanation

### Subsection

- Item one
- Item two
- Item three
```

### 5. Hierarchy/Layering

> Configuration layers override each other (enterprise → project → user → local).

#### Stability Rationale (Hierarchy)

Layered configuration is a fundamental software pattern used across all systems:

- CSS cascades
- Environment variable inheritance
- Git config (system → global → local)
- Package manager settings

This pattern exists because it balances defaults with customization.

#### Application (Hierarchy)

**Memory hierarchy (highest to lowest priority):**

1. **Enterprise** - Organization-wide policies
2. **Project** - Repository-specific settings (CLAUDE.md at root)
3. **User** - Personal preferences (~/.claude/CLAUDE.md)
4. **Local** - Machine-specific overrides

**Conflict resolution:**

- Higher priority overrides lower
- More specific overrides more general
- Later content can override earlier (within same file)

**Best practices:**

- Put team standards at project level
- Put personal preferences at user level
- Document which level each setting belongs to
- Avoid conflicts by using appropriate levels

### 6. Token Efficiency

> Context is finite - be efficient with tokens.

#### Stability Rationale (Tokens)

LLM context windows have hard limits. Even as they grow (4k → 8k → 100k → 200k), efficiency matters because:

- Larger contexts increase cost
- More tokens increase latency
- Relevant information can be diluted by noise
- There's always a limit somewhere

Token efficiency will always be valuable.

#### Application (Tokens)

**Token-saving strategies:**

| Strategy | Savings | Example |
| -------- | ------- | ------- |
| Link don't duplicate | 50-90% | Link to docs instead of copying |
| Progressive disclosure | 30-70% | Load details on demand |
| Remove redundancy | 10-30% | Eliminate repeated content |
| Concise writing | 10-20% | "Use X" vs "You should use X" |

**Token budget allocation:**

```text
Total budget: ~50-60k tokens

Always-loaded: ~10-15k tokens (20-25%)
├─ CLAUDE.md hub: ~3-5k
└─ Core memory files: ~7-10k

On-demand: ~30-40k tokens (60-70%)
├─ Detailed guides
├─ Reference documentation
└─ Examples and templates

Reserved: ~5-10k tokens (10-15%)
└─ Buffer for conversation context
```

**Monitoring token usage:**

- Estimate tokens: ~1.3 tokens per word for English
- Track file sizes and document in CLAUDE.md
- Review periodically and trim bloat

## Summary Table

| Principle | Core Idea | Why Stable |
| --------- | --------- | ---------- |
| Progressive Disclosure | Load on-demand | Context windows are finite |
| Strategic Emphasis | CRITICAL/NEVER/MUST | Human priority signaling |
| Specificity | Concrete over vague | Actionability is universal |
| Structure | Headings/bullets/tables | Information processing |
| Hierarchy | Layers override | Configuration patterns |
| Token Efficiency | Be concise | Resources are limited |

## Related

- [SKILL.md](../SKILL.md) - Main hub with quick reference
- [Keyword Registry](keyword-registry.md) - For querying official docs
- [Common Patterns](common-patterns.md) - Implementation patterns

---

**Last Updated:** 2025-11-26
