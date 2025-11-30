---
description: Deep codebase analysis using codebase-analyst agent for patterns, architecture, and implementation details
argument-hint: [scope or pattern description]
allowed-tools: Task, Read, Glob, Grep, Bash
---

# Codebase Analysis Command

Perform comprehensive codebase analysis to understand patterns, architecture, and implementation details.

## Instructions

**Use the codebase-analyst agent to perform deep codebase analysis.**

The codebase-analyst agent provides:

- **Pattern recognition** across multiple files
- **Architecture analysis** (dependencies, structure, layers)
- **Implementation detail exploration** (how code works)
- **Cross-cutting concern analysis** (error handling, logging, auth)
- **Technical debt identification**

**Invoke the agent based on the arguments provided:**

```text
$ARGUMENTS

Based on the arguments, determine the analysis scope:

If a topic/concept provided (e.g., "authentication", "error handling"):
  - Find all code related to that concept
  - Analyze patterns, implementations, and consistency
  - Identify entry points, data flows, and dependencies

If a directory/path provided (e.g., "src/components/"):
  - Analyze architecture and structure of that module
  - Identify patterns and conventions used
  - Map internal dependencies

If a question provided (e.g., "how does the API handle errors?"):
  - Research and answer the architectural question
  - Provide code references and examples
  - Explain the design decisions

If no arguments:
  - Provide high-level codebase overview
  - Identify main modules and their relationships
  - Highlight key patterns and conventions
```

## Examples

### Analyze a Concept

```text
/code-quality:analyze authentication
/code-quality:analyze "error handling patterns"
/code-quality:analyze "how API endpoints work"
```

### Analyze a Module

```text
/code-quality:analyze src/components/
/code-quality:analyze "the database layer"
```

### Answer Architectural Questions

```text
/code-quality:analyze "how does caching work in this codebase?"
/code-quality:analyze "what design patterns are used?"
```

### General Overview

```text
/code-quality:analyze
```

## Output Format

The agent returns analysis findings:

```markdown
## Analysis: [Topic/Scope]

### Overview
[High-level summary of findings]

### Key Patterns
- [Pattern 1]: [Description and locations]
- [Pattern 2]: [Description and locations]

### Architecture
[Structure, layers, dependencies]

### Code References
- `path/to/file.ext:line` - [What this shows]

### Recommendations
[Suggestions for understanding or improving]
```

## Command Design Notes

This command delegates to the codebase-analyst agent which specializes in deep exploration and pattern recognition. It's read-only and focuses on understanding rather than modification.
