# Tool Restriction Patterns

Query patterns for finding official allowed-tools documentation and examples.

## Official Documentation Query

For complete allowed-tools guidance, query official-docs:

```text
Find documentation about allowed-tools configuration using keywords: allowed-tools, tool restrictions, tool access control
```

## Common Queries

**For allowed-tools field specification:**
**Query official-docs:** "Find official documentation about allowed-tools YAML frontmatter field"

**For implementation examples:**
**Query official-docs:** "Find allowed-tools implementation examples and use cases"

**For tool list and availability:**
**Query official-docs:** "Find list of available tools for allowed-tools configuration"

**For restriction patterns:**
**Query official-docs:** "Find tool restriction patterns and best practices"

## Tool Restriction Principles (Metadata Only)

> **Note:** This is a quick summary. Query official-docs for authoritative specification.

**Core Concept:**
Use `allowed-tools` to limit which tools Claude can use within a skill.

**Common Patterns:**

1. **Read-Only Analysis** → `allowed-tools: Read, Grep, Glob`
2. **Audit Workflows** → `allowed-tools: Read, Grep, Glob` (prevent modifications)
3. **Safe Exploration** → `allowed-tools: Read, Grep, Glob` (no writes)
4. **Documentation Skills** → `allowed-tools: Read, Grep, Glob, WebFetch, WebSearch` (research + read)
5. **File Generation** → `allowed-tools: Read, Write, Glob` (create files, no edits)
6. **Interactive Planning** → `allowed-tools: Read, Grep, Glob, AskUserQuestion, EnterPlanMode, ExitPlanMode`
7. **Task Delegation** → `allowed-tools: Read, Task, Skill` (delegate to subagents)

**Basic Pattern:**

```yaml
---
name: readonly-analyzer
description: Analyze code without modifications
allowed-tools: Read, Grep, Glob
---
```

> **Verify:** YAML syntax requirements may evolve. Query official-docs for current specification before using.

**For detailed implementation guidance, complete tool list, and best practices**, query official-docs using the patterns above.

## Decision Tree

**When to use allowed-tools?**

1. **Read-only analysis required** → Restrict to Read, Grep, Glob
2. **Audit/review workflow** → Prevent modifications
3. **Safety-critical operations** → Limit tool access
4. **Specialized skill** → Restrict to relevant tools only

For implementation workflow, query official-docs: "Find allowed-tools configuration workflow and patterns"
