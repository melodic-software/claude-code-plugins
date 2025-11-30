# Subagent/Agent Validation Checklist

**Source:** Official Claude Code documentation (code.claude.com, platform.claude.com)

Use this checklist before creating or renaming agents. All rules are extracted from official documentation.

## YAML Frontmatter Requirements

### `name` Field (Required)

- [ ] **Lowercase letters and hyphens only**
- [ ] **Maximum 64 characters** (same as skills)
- [ ] **No reserved words:** Cannot contain "anthropic" or "claude"
- [ ] **Unique identifier** for the agent

**Valid examples:**
- `code-reviewer`
- `debugger`
- `data-scientist`
- `test-runner`
- `docs-researcher`

**Invalid examples:**
- `Code-Reviewer` (uppercase letters)
- `claude-helper` (reserved word "claude")
- `my agent` (spaces)

### `description` Field (Required)

- [ ] **Natural language description** of the subagent's purpose
- [ ] **Drives automatic delegation** - Claude uses this to decide when to use the agent
- [ ] **Written in third person**
- [ ] **Includes "when to use" guidance**
- [ ] **Consider using "PROACTIVELY" or "MUST BE USED"** for important agents

**Good examples:**
```yaml
description: Expert code review specialist. Proactively reviews code for quality, security, and maintainability. Use immediately after writing or modifying code.
```

```yaml
description: PROACTIVELY use when researching Claude Code features, searching official documentation, or finding canonical guidance on Claude Code topics.
```

**Bad examples:**
```yaml
description: Reviews code  # Too vague
description: I help with debugging  # First person
```

### Optional Fields

| Field | Description | Values |
|-------|-------------|--------|
| `tools` | Tools the agent can use | Tool names (e.g., `Read, Edit, Bash`) |
| `model` | Model to use | `inherit`, `sonnet`, `haiku`, `opus` |
| `color` | Agent color in UI | Color name (e.g., `purple`, `blue`) |
| `skills` | Auto-load skills | Skill names |

## Priority Resolution

When agent names conflict:

| Type | Location | Priority |
|------|----------|----------|
| Project subagents | `.claude/agents/` | Highest |
| CLI-defined | `--agents` flag | Medium |
| User subagents | `~/.claude/agents/` | Lower |

## File Naming

- [ ] **File name should match agent purpose** (e.g., `code-reviewer.md`)
- [ ] **Use `.md` extension**
- [ ] **Kebab-case for file names**

## Pre-Creation Verification

Before creating a new agent:

1. [ ] Check name is unique (won't conflict with other agents)
2. [ ] Verify no reserved words in name
3. [ ] Description clearly explains when Claude should delegate to this agent
4. [ ] Tools list includes only necessary tools
5. [ ] Model selection is appropriate for task complexity

## Common Mistakes to Avoid

- Using "anthropic" or "claude" in agent names
- Vague descriptions that don't guide delegation
- Not specifying tools (defaults may be too broad or too narrow)
- Using first/second person in descriptions
- Not including delegation triggers in description

---

**Last Updated:** 2025-11-30
**Source References:**
- `code-claude-com/docs/en/sub-agents.md`
- `platform-claude-com/docs/en/agent-sdk/subagents.md`
- `platform-claude-com/docs/en/agents-and-tools/agent-skills/best-practices.md`
