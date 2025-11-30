# Keyword Registry Reference

## Overview

This document provides a comprehensive keyword registry for efficiently querying the `official-docs` skill for memory-related documentation. Use these keywords to find official documentation quickly.

## How to Use This Registry

1. Identify the topic you need information about
2. Find the relevant section below
3. Use the provided keywords in your official-docs query
4. Example: "Find documentation about `<keywords>`"

## Core Memory System

### CLAUDE.md Files

**Keywords:** `CLAUDE.md`, `static memory`, `memory files`, `project memory`

**Example queries:**

```text
Find documentation about CLAUDE.md static memory files
Find documentation about creating project memory with CLAUDE.md
```

**Topics covered:**

- What CLAUDE.md files are
- How they're loaded into context
- File locations and precedence

### Memory Hierarchy

**Keywords:** `memory hierarchy`, `enterprise memory`, `project memory`, `user memory`, `local memory`, `memory precedence`

**Example queries:**

```text
Find documentation about memory hierarchy and precedence
Find documentation about enterprise project user memory levels
```

**Topics covered:**

- Four-tier hierarchy (enterprise → project → user → local)
- Override precedence rules
- When to use each level

### Memory System Overview

**Keywords:** `memory system`, `static memory overview`, `memory architecture`

**Example queries:**

```text
Find documentation about Claude Code memory system architecture
Find documentation about static memory overview
```

**Topics covered:**

- How memory integrates with Claude Code
- System design and components
- Memory loading behavior

## Import Syntax

### Basic Import Syntax

**Keywords:** `import syntax`, `@ references`, `@ imports`, `file imports`

**Example queries:**

```text
Find documentation about CLAUDE.md import syntax
Find documentation about @ file references in memory
```

**Topics covered:**

- `@path/to/file.md` syntax
- Relative vs absolute paths
- File extension requirements

### Recursive Lookup

**Keywords:** `recursive lookup`, `import depth`, `nested imports`, `import chain`

**Example queries:**

```text
Find documentation about recursive memory lookup behavior
Find documentation about import depth limits
```

**Topics covered:**

- How nested imports work
- Maximum import depth
- Import chain behavior

### Import Behavior

**Keywords:** `import behavior`, `always loaded`, `on-demand loading`, `import processing`

**Example queries:**

```text
Find documentation about always-loaded vs on-demand memory imports
Find documentation about import processing behavior
```

**Topics covered:**

- When imports are processed
- Always-loaded (@) vs on-demand (no @) patterns
- Import timing and order

## Memory Commands

### /init Command

**Keywords:** `/init command`, `initialize memory`, `create CLAUDE.md`

**Example queries:**

```text
Find documentation about /init command for creating CLAUDE.md
Find documentation about initializing memory files
```

**Topics covered:**

- Creating new CLAUDE.md files
- Interactive initialization
- Default content generation

### /memory Command

**Keywords:** `/memory command`, `edit memory`, `memory editor`

**Example queries:**

```text
Find documentation about /memory command for editing
Find documentation about memory editing workflow
```

**Topics covered:**

- Opening memory for editing
- Memory modification workflow
- Editor integration

### # Shortcut

**Keywords:** `# shortcut`, `quick memory add`, `hash shortcut`

**Example queries:**

```text
Find documentation about # shortcut for adding to memory
Find documentation about quick memory additions
```

**Topics covered:**

- Quick instruction addition
- Shortcut syntax
- When to use #

## Best Practices

### Memory Organization

**Keywords:** `memory organization`, `memory structure`, `organizing CLAUDE.md`

**Example queries:**

```text
Find documentation about organizing CLAUDE.md files
Find documentation about memory structure best practices
```

**Topics covered:**

- File organization patterns
- Content structure recommendations
- Naming conventions

### Memory Tuning

**Keywords:** `memory tuning`, `CLAUDE.md tuning`, `memory optimization`, `prompt tuning`

**Example queries:**

```text
Find documentation about tuning CLAUDE.md for effectiveness
Find documentation about memory optimization techniques
```

**Topics covered:**

- Iterating on memory content
- Testing effectiveness
- Refinement strategies

### Memory Best Practices

**Keywords:** `memory best practices`, `CLAUDE.md best practices`, `effective memory`

**Example queries:**

```text
Find documentation about CLAUDE.md best practices
Find documentation about effective memory usage
```

**Topics covered:**

- Official recommendations
- Common patterns
- Anti-patterns to avoid

## Agent SDK Integration

### settingSources

**Keywords:** `settingSources`, `memory API`, `SDK memory`

**Example queries:**

```text
Find documentation about Agent SDK settingSources
Find documentation about programmatic memory access
```

**Topics covered:**

- Accessing memory programmatically
- SDK integration patterns
- settingSources configuration

### SDK Memory Patterns

**Keywords:** `Agent SDK memory`, `SDK memory patterns`, `programmatic memory`

**Example queries:**

```text
Find documentation about using memory in Agent SDK
Find documentation about SDK memory integration patterns
```

**Topics covered:**

- Memory in SDK context
- Integration approaches
- Best practices for SDK

## File Locations

### Project Memory Location

**Keywords:** `project memory location`, `CLAUDE.md location`, `memory file paths`

**Example queries:**

```text
Find documentation about CLAUDE.md file locations
Find documentation about where project memory files live
```

**Topics covered:**

- Standard file paths
- Platform-specific locations
- Discovery behavior

### User Memory Location

**Keywords:** `user memory location`, `personal memory`, `~/.claude`

**Example queries:**

```text
Find documentation about user memory file locations
Find documentation about personal CLAUDE.md location
```

**Topics covered:**

- User home directory paths
- Cross-platform locations
- Personal vs project memory

## Troubleshooting

### Memory Loading Issues

**Keywords:** `memory loading`, `memory not loading`, `import errors`

**Example queries:**

```text
Find documentation about troubleshooting memory loading issues
Find documentation about fixing import errors
```

**Topics covered:**

- Common loading problems
- Diagnostic steps
- Resolution strategies

### Syntax Issues

**Keywords:** `syntax errors`, `YAML frontmatter`, `memory syntax`

**Example queries:**

```text
Find documentation about CLAUDE.md syntax requirements
Find documentation about fixing memory syntax errors
```

**Topics covered:**

- Syntax requirements
- Common mistakes
- Validation approaches

## Quick Reference Table

| Topic | Primary Keywords | Secondary Keywords |
| ----- | ---------------- | ------------------ |
| Core System | `CLAUDE.md`, `static memory` | `memory files`, `project memory` |
| Hierarchy | `memory hierarchy` | `enterprise`, `project`, `user`, `local` |
| Imports | `import syntax`, `@ references` | `recursive lookup`, `import depth` |
| Commands | `/init`, `/memory`, `# shortcut` | `create`, `edit`, `quick add` |
| Best Practices | `memory best practices` | `tuning`, `optimization`, `organization` |
| Agent SDK | `settingSources`, `SDK memory` | `programmatic`, `API` |
| Troubleshooting | `memory loading`, `import errors` | `syntax`, `not loading` |

## Related

- [SKILL.md](../SKILL.md) - Main hub with quick reference
- [Stable Principles](stable-principles.md) - Timeless memory principles
- [Common Patterns](common-patterns.md) - Implementation patterns

---

**Last Updated:** 2025-11-26
