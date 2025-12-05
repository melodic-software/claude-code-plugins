# Component Validation Checklist

Use this checklist to validate each component before marking it complete.

**CRITICAL**: For every component, the docs-management checkbox must be checked FIRST before proceeding.

---

## Skills Checklist

- [ ] **docs-management FIRST**: Invoke `claude-ecosystem:docs-management` skill, then run:
  ```bash
  python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search skill frontmatter allowed-tools
  ```
- [ ] **Name**: Max 64 chars, lowercase letters + hyphens only
- [ ] **Name**: Does NOT contain "anthropic" or "claude"
- [ ] **Name**: Uses noun-phrase naming (e.g., `context-audit` not `audit-context`)
- [ ] **Description**: Max 1024 chars, non-empty
- [ ] **Description**: Third person, describes what it does AND when to use it
- [ ] **allowed-tools**: Comma-separated string (NOT array)
- [ ] **Frontmatter**: Valid YAML with `---` delimiters

### Skill Frontmatter Template

```yaml
---
name: skill-name-here
description: Does X and Y. Use when working with Z or when the user mentions A, B, C.
allowed-tools: Read, Grep, Glob
---
```yaml

---

## Agents Checklist

- [ ] **docs-management FIRST**: Invoke `claude-ecosystem:docs-management` skill, then run:
  ```bash
  python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search subagent tools model frontmatter
  ```
- [ ] **Name**: Lowercase letters and hyphens only
- [ ] **Description**: Natural language, include "use proactively" if desired
- [ ] **tools**: Array syntax OR comma-separated (both work per official docs)
- [ ] **model**: One of `opus` (for planning/orchestration), `sonnet` (for implementation), `haiku` (for fast tasks), or `inherit`
- [ ] **Model Selection**: Planning/orchestration agents should use `opus`
- [ ] **Constraint**: Does NOT attempt to spawn other subagents

### Agent Frontmatter Template

```yaml
---
name: agent-name-here
description: Clear description of when to use this agent.
tools: [Read, Write, Grep, Glob, Bash]
model: sonnet
---
```yaml

---

## Commands Checklist

- [ ] **docs-management FIRST**: Invoke `claude-ecosystem:docs-management` skill, then run:
  ```bash
  python plugins/claude-ecosystem/skills/docs-management/scripts/core/find_docs.py search slash command frontmatter description
  ```
- [ ] **Frontmatter**: Has `description` field (REQUIRED for SlashCommand tool visibility)
- [ ] **Frontmatter**: Has `argument-hint` field if command takes arguments
- [ ] **Name**: Uses kebab-case (NOT underscores)
- [ ] **Name**: Uses verb-phrase naming (e.g., `/create-plan` not `/plan-creation`)
- [ ] **Arguments**: Uses `$ARGUMENTS` or `$1`, `$2` patterns
- [ ] **File**: Located in `commands/` folder

### Command Frontmatter Template

```yaml
---
description: Brief description of what this command does
argument-hint: [arg1] [arg2] (optional)
allowed-tools: Read, Grep, Glob (optional)
---
```

### Command Content Template

```markdown
---
description: Brief description of what this command does
argument-hint: [target] [options]
---

# Command Name

## Arguments
- `$1`: First argument description
- `$ARGUMENTS`: All arguments description

## Instructions
[Command content - can invoke skills or agents]
```

---

## Memory Files Checklist

- [ ] **Location**: Appropriate folder based on scope
- [ ] **Import syntax**: Can be referenced with `@path/to/file.md`
- [ ] **Progressive disclosure**: Doesn't dump everything upfront
- [ ] **Hierarchy**: Fits within memory hierarchy pattern
- [ ] **docs-management**: Validated against official Claude Code docs

---

## Hooks Checklist

- [ ] **Event**: Valid hook event type
- [ ] **Matcher**: Pattern matches expected tools/events
- [ ] **Action**: Clear block vs log decision
- [ ] **docs-management**: Validated against official Claude Code docs

---

## Output Styles Checklist

- [ ] **Frontmatter**: Valid YAML with name and description
- [ ] **keep-coding-instructions**: Set if extending default behavior
- [ ] **docs-management**: Validated against official Claude Code docs

---

## MCP Configs Checklist

- [ ] **Server**: Valid server configuration
- [ ] **Tools**: Properly named and documented
- [ ] **OAuth**: If needed, properly configured
- [ ] **docs-management**: Validated against official Claude Code docs

---

## TypeScript SDK Checklist

- [ ] **Options class**: Uses `ClaudeAgentOptions` (NOT `ClaudeCodeOptions`)
- [ ] **System prompt**: Explicitly set (not automatic like Python)
- [ ] **CLAUDE.md loading**: Uses `settingSources: ["project"]` if needed
- [ ] **Tool creation**: Uses `tool()` with Zod schemas
- [ ] **Query function**: Uses `query()` async generator
- [ ] **Case convention**: Uses camelCase (not snake_case)

---

## SDK-Only Pattern Checklist (Lessons 11-12)

- [ ] **Orchestration patterns**: If component spawns agents, it MUST be SDK-only
- [ ] **Fleet management**: Agent lifecycle management is SDK-only
- [ ] **Multi-agent coordination**: Nested agent spawning is SDK-only
- [ ] **Documentation**: SDK-only components documented with implementation path
- [ ] **Reference implementation**: Points to companion repo example
- [ ] **Guidance skill**: Created to help users build SDK solutions (if applicable)

### SDK-Only Decision Tree

```

Does the component need to spawn other agents?
  └── YES → SDK-only (subagents cannot spawn subagents)
  └── NO  → Can be subagent

Does the component manage agent lifecycle?
  └── YES → SDK-only (requires database backend)
  └── NO  → Can be subagent

Does the component coordinate multiple agents simultaneously?
  └── YES → SDK-only (orchestration pattern)
  └── NO  → Can be subagent

```yaml

---

## Built-in Agent Overlap Checklist

Before creating a new agent, verify it doesn't duplicate functionality from existing claude-ecosystem agents.

### Check Against Built-in Agents

| Built-in Agent | Purpose | Overlap Indicators |
| ---------------- | --------- | ------------------- |
| `Explore` | Codebase exploration | File searching, pattern finding, structure analysis |
| `Plan` | Implementation planning | Architecture design, step-by-step plans |
| `code-reviewer` | Code quality review | Bug detection, style issues, security |
| `codebase-analyst` | Deep codebase analysis | Patterns, architecture, dependencies |
| `debugger` | Root cause analysis | Error investigation, stack traces |
| `history-reviewer` | Git history exploration | Blame, log, diff, commit analysis |

- [ ] **No exploration overlap**: Proposed agent doesn't duplicate Explore functionality
- [ ] **No planning overlap**: Proposed agent doesn't duplicate Plan functionality
- [ ] **No review overlap**: Proposed agent doesn't duplicate code-reviewer functionality
- [ ] **No analysis overlap**: Proposed agent doesn't duplicate codebase-analyst functionality
- [ ] **No debug overlap**: Proposed agent doesn't duplicate debugger functionality
- [ ] **No git overlap**: Proposed agent doesn't duplicate history-reviewer functionality
- [ ] **Unique value**: Proposed agent provides distinct value not covered by built-ins

### Resolution When Overlap Exists

1. **Use built-in instead**: Prefer existing agents when they cover the use case
2. **Extend via skill**: Create a skill that the built-in agent can use
3. **Specialize narrowly**: If new agent needed, ensure it's clearly differentiated
4. **Document distinction**: Explain why built-in doesn't cover the use case

---

## General Quality Checks

- [ ] **No duplicates**: Doesn't duplicate existing plugin functionality
- [ ] **Actionable**: Provides real value, not just documentation
- [ ] **Tested**: Component works as expected
- [ ] **Documented**: Purpose and usage are clear
- [ ] **Tracker updated**: MASTER-TRACKER.md reflects this component

---

## Common Mistakes to Avoid

| Mistake | Correct Pattern |
| --------- | ----------------- |
| `allowed-tools: [Read, Write]` | `allowed-tools: Read, Write` |
| `tools: Read, Write, Bash` | `tools: [Read, Write, Bash]` |
| `/create_plan` | `/create-plan` |
| `ClaudeCodeOptions` | `ClaudeAgentOptions` |
| `rd-framework` | `reduce-delegate-framework` |
| Subagent spawning subagents | SDK-only for orchestration |

---

## Validation Command

Before finalizing any component, invoke the docs-management skill:

```

Invoke skill: docs-management

Then search for: [component type] [specific feature]

```text

This ensures all components align with official Claude Code documentation.
