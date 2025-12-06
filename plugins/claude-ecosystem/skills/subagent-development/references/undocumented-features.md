# Undocumented Subagent Features

> **WARNING: USE AT YOUR OWN RISK**
>
> These features are **NOT** in official Claude Code documentation and may:
>
> - Change without notice in ANY Claude Code update
> - Stop working entirely without warning
> - Have undiscovered bugs or edge cases
> - Behave differently across versions
>
> **Do NOT rely on these features for production workflows.**
>
> **Last Verified:** 2025-12-05

---

## Overview

This document catalogs undocumented YAML frontmatter fields that work in Claude Code subagent definition files. These have been discovered through experimentation and observation.

## Color Property

### Description

The `color` property sets the UI color for subagent display in Claude Code's terminal output.

### Syntax

```yaml
---
name: my-agent
description: Agent description
tools: Read, Grep, Glob
model: haiku
color: blue
---
```

### Valid Values

| Color | Hex Approximation | Typical Usage |
| ----- | ----------------- | ------------- |
| `red` | #FF0000 | Critical/error handling agents |
| `blue` | #0000FF | Code quality, analysis agents |
| `green` | #00FF00 | Research, information gathering |
| `yellow` | #FFFF00 | Warning/attention agents |
| `purple` | #800080 | Documentation, meta, auditing agents |
| `orange` | #FFA500 | Generation/creation agents |
| `pink` | #FFC0CB | User-facing/communication agents |
| `cyan` | #00FFFF | Utility agents |

### Placement

The `color` field should be placed after `model` in the YAML frontmatter:

```yaml
---
name: example-agent
description: Description here
tools: Read, Grep
model: haiku
color: purple
---
```

### Repository Color Standard

This repository uses semantic color assignments:

| Category | Color | Agents Using |
| -------- | ----- | ------------ |
| Documentation/Meta | purple | docs-researcher, skill-auditor, agent-auditor, command-auditor |
| Code Quality | blue | code-reviewer, codebase-analyst, debugger |
| Research | green | mcp-research, platform-docs-researcher |

**Future Reserved:**

- orange: Generation/creation
- red: Critical/error handling
- yellow: Warning/attention
- pink: User-facing/communication
- cyan: Utility

## Permission Mode Property

### Description

The `permissionMode` property controls how the agent handles permission prompts.

### Syntax

```yaml
---
name: my-agent
description: Agent description
tools: Read, Edit, Bash
model: sonnet
permissionMode: acceptEdits
---
```

### Valid Values

| Mode | Description | Use Case |
| ---- | ----------- | -------- |
| `default` | Normal permission prompting | Standard agents needing user approval |
| `acceptEdits` | Auto-accept file edit operations | Agents that need to modify files autonomously |
| `bypassPermissions` | Skip all permission prompts | Fully autonomous agents (use with caution) |
| `plan` | Read-only planning mode | Agents that should only analyze, not modify |
| `ignore` | Ignore permission configuration | Debugging or special cases |

### Security Considerations

**Caution:** Using `bypassPermissions` grants the agent significant autonomy. Only use when:

- The agent's tools are already restricted
- The agent's purpose is well-defined
- The potential impact is understood

**Recommended Patterns:**

| Agent Purpose | Recommended Mode |
| ------------- | ---------------- |
| Read-only analysis | `plan` |
| Code review | `default` or `plan` |
| Autonomous file editing | `acceptEdits` |
| Fully automated workflows | `bypassPermissions` (with tool restrictions) |

## Skills Property

### Description

The `skills` property auto-loads specified skills when the agent starts.

### Syntax

```yaml
---
name: my-agent
description: Agent description
tools: Read, Glob, Grep, Skill
model: haiku
skills: skill-development, docs-management
---
```

### Behavior

- Skills are loaded in order specified
- Agent's tool list should include `Skill` tool if using skills
- Skills provide context but don't restrict other capabilities
- Multiple skills separated by comma

### Common Patterns

| Agent Type | Skills to Auto-Load |
| ---------- | ------------------- |
| Documentation auditor | skill-development, docs-management |
| Command auditor | command-development |
| Agent auditor | subagent-development |
| Code reviewer | code-reviewing (if exists) |

### Example

```yaml
---
name: skill-auditor
description: Audits skills for quality and compliance
tools: Read, Glob, Grep, Skill
model: haiku
color: purple
skills: skill-development
---
```

## Discovery Notes

These features were discovered through:

1. **Observation:** Noting Claude Code source behavior
2. **Experimentation:** Testing various field values
3. **Community reports:** User-reported findings
4. **Plugin development:** Internal Anthropic patterns

## Stability Warning

**These features are undocumented because:**

- They may change without notice
- They may not work in all versions
- They may have edge cases or bugs
- Official documentation takes precedence

**Best practices:**

1. Use these features for enhancement, not critical functionality
2. Have fallback behavior if features stop working
3. Monitor Claude Code release notes for changes
4. Report issues if features behave unexpectedly

## Related Resources

- `references/validation-checklist.md` - Official YAML fields and audit criteria
- `SKILL.md` - Color Property section (repository standard)
- Official docs via `docs-management` skill - Canonical YAML frontmatter

---

**Last Updated:** 2025-12-05
**Discovery Status:** Active - features may be added/updated
