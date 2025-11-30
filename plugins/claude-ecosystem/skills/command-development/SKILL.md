---
name: command-development
description: Central authority for Claude Code slash commands. Covers built-in commands, custom slash commands (project and personal), plugin commands, MCP slash commands, SlashCommand tool, frontmatter configuration, arguments ($ARGUMENTS, $1, $2), bash execution, file references, namespacing, and skills vs slash commands comparison. Assists with creating custom commands, configuring command behavior, understanding command types, and troubleshooting command issues. Delegates 100% to docs-management skill for official documentation.
allowed-tools: Read, Glob, Grep, Skill
---

# Slash Commands Meta Skill

> ## 🚨 MANDATORY: Invoke docs-management First
>
> **STOP - Before providing ANY response about slash commands:**
>
> 1. **INVOKE** `docs-management` skill
> 2. **QUERY** for the user's specific topic
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded
>
> **Skipping this step results in outdated or incorrect information.**
>
> ### Verification Checkpoint
>
> Before responding, verify:
>
> - [ ] Did I invoke docs-management skill?
> - [ ] Did official documentation load?
> - [ ] Is my response based EXCLUSIVELY on official docs?
>
> If ANY checkbox is unchecked, STOP and invoke docs-management first.

## Overview

Central authority for Claude Code slash commands. This skill uses **100% delegation to docs-management** - it contains NO duplicated official documentation.

**Architecture:** Pure delegation with keyword registry. All official documentation is accessed via docs-management skill queries.

## When to Use This Skill

**Keywords:** slash commands, custom commands, built-in commands, project commands, personal commands, plugin commands, MCP commands, SlashCommand tool, command frontmatter, allowed-tools, argument-hint, $ARGUMENTS, bash execution, file references, namespacing, skills vs commands

**Use this skill when:**

- Creating custom slash commands
- Understanding built-in commands (/init, /compact, /memory, etc.)
- Configuring command frontmatter (allowed-tools, description, model)
- Using arguments in commands ($ARGUMENTS, $1, $2)
- Executing bash commands in slash commands
- Referencing files in commands (@file syntax)
- Understanding namespacing and organization
- Working with plugin commands
- Using MCP prompts as slash commands
- Configuring SlashCommand tool permissions
- Deciding between skills vs slash commands
- Troubleshooting command issues

## Keyword Registry for docs-management Queries

Use these keywords when querying docs-management skill for official documentation:

### Core Concepts

| Topic | Keywords |
| ----- | -------- |
| Overview | "slash commands", "command overview" |
| Built-in Commands | "built-in slash commands", "built-in commands table" |
| Custom Commands | "custom slash commands", "command creation" |

### Command Types

| Topic | Keywords |
| ----- | -------- |
| Project Commands | "project commands", ".claude/commands" |
| Personal Commands | "personal commands", "~/.claude/commands" |
| Plugin Commands | "plugin commands", "plugin slash commands" |
| MCP Commands | "MCP slash commands", "mcp__server__prompt" |
| MCP Permissions | "MCP permissions wildcards", "mcp__servername", "approve all tools" |

### Configuration

| Topic | Keywords |
| ----- | -------- |
| Frontmatter | "command frontmatter", "allowed-tools", "argument-hint", "description" |
| Model Selection | "command model", "model frontmatter" |
| Tool Restrictions | "allowed-tools commands", "command permissions" |

### Features

| Topic | Keywords |
| ----- | -------- |
| Arguments | "$ARGUMENTS", "command arguments", "$1 $2 positional" |
| Bash Execution | "bash command execution", "! prefix commands" |
| File References | "file references commands", "@ prefix files" |
| Namespacing | "command namespacing", "subdirectory commands" |
| Thinking Mode | "thinking mode commands", "extended thinking slash" |

### SlashCommand Tool

| Topic | Keywords |
| ----- | -------- |
| Tool Overview | "SlashCommand tool", "programmatic command execution" |
| Permissions | "SlashCommand permission rules", "disable SlashCommand" |
| Character Budget | "character budget limit", "SLASH_COMMAND_TOOL_CHAR_BUDGET", "15000 characters" |
| Disable Commands | "disable-model-invocation", "disable specific commands" |

### Comparisons

| Topic | Keywords |
| ----- | -------- |
| Skills vs Commands | "skills vs slash commands", "when to use commands vs skills" |

## Quick Decision Tree

**What do you want to do?**

1. **Create a custom command** -> Query docs-management: "custom slash commands", "command creation"
2. **Configure command frontmatter** -> Query docs-management: "command frontmatter", "allowed-tools"
3. **Use arguments in commands** -> Query docs-management: "$ARGUMENTS", "command arguments"
4. **Execute bash in commands** -> Query docs-management: "bash command execution", "! prefix"
5. **Reference files in commands** -> Query docs-management: "file references commands", "@ prefix"
6. **Understand namespacing** -> Query docs-management: "command namespacing", "subdirectory commands"
7. **Work with plugin commands** -> Query docs-management: "plugin commands", "plugin slash commands"
8. **Use MCP as commands** -> Query docs-management: "MCP slash commands", "mcp__server__prompt"
9. **Configure SlashCommand tool** -> Query docs-management: "SlashCommand tool", "SlashCommand permissions"
10. **Choose skills vs commands** -> Query docs-management: "skills vs slash commands"
11. **View built-in commands** -> Query docs-management: "built-in slash commands table"
12. **Troubleshoot command issues** -> Query docs-management: "slash commands troubleshooting" + specific issue
13. **Configure MCP command permissions** -> Query docs-management: "MCP permissions wildcards", "mcp__servername"

## Topic Coverage

### Built-in Commands

- Complete command reference table
- Common commands (/init, /compact, /memory, /clear, /cost)
- Session management (/resume, /exit, /rewind)
- Configuration (/config, /permissions, /model)
- MCP and plugins (/mcp, /plugin, /agents)

### Custom Commands

- Project commands (.claude/commands/)
- Personal commands (~/.claude/commands/)
- Command file format (markdown)
- Naming conventions (filename = command name)

### Command Frontmatter

- allowed-tools: Tool restrictions
- argument-hint: Argument display hints
- description: Command description
- model: Model selection
- disable-model-invocation: Prevent SlashCommand tool access

### Arguments

- $ARGUMENTS: All arguments as single string
- $1, $2, $3...: Positional arguments
- Combining argument patterns
- Default values and handling

### Bash Execution

- ! prefix for inline bash
- Including command output in context
- Required allowed-tools configuration
- Git commit example patterns

### File References

- @ prefix for file inclusion
- Single and multiple file references
- Path resolution behavior

### Namespacing

- Subdirectory organization
- (project) vs (user) indicators
- Conflict resolution rules
- Namespace display in /help

### Plugin Commands

- Plugin command structure
- Namespaced invocation (/plugin-name:command)
- Plugin marketplace integration
- Command distribution

### MCP Commands

- MCP prompt to command mapping
- /mcp__server__prompt pattern
- Dynamic discovery
- Authentication and permissions

### SlashCommand Tool Configuration

- Programmatic command execution
- Supported command requirements
- Permission rules (exact match, prefix match)
- Character budget limits
- Disabling tool access

### Skills vs Slash Commands

- Complexity comparison
- Structure differences
- Discovery patterns (explicit vs automatic)
- When to use each approach

## Delegation Patterns

### Standard Query Pattern

```text
User asks: "How do I create a custom command?"

1. Invoke docs-management skill
2. Use keywords: "custom slash commands", "command creation"
3. Load official documentation
4. Provide guidance based EXCLUSIVELY on official docs
```

### Multi-Topic Query Pattern

```text
User asks: "I want a command that runs git status and uses arguments"

1. Invoke docs-management skill with multiple queries:
   - "bash command execution", "! prefix commands"
   - "$ARGUMENTS", "command arguments"
   - "allowed-tools commands"
2. Synthesize guidance from official documentation
```

### Comparison Query Pattern

```text
User asks: "Should I use a skill or slash command for code review?"

1. Invoke docs-management skill
2. Use keywords: "skills vs slash commands", "when to use commands vs skills"
3. Guide user through decision criteria from official docs
```

## Troubleshooting Quick Reference

| Issue | Keywords for docs-management |
| ----- | ------------------------ |
| Command not found | "custom slash commands", ".claude/commands" |
| Arguments not working | "$ARGUMENTS", "positional arguments" |
| Bash not executing | "bash command execution", "allowed-tools" |
| Files not included | "file references commands", "@ prefix" |
| SlashCommand not invoking | "SlashCommand tool", "disable-model-invocation" |
| Namespace conflicts | "command namespacing", "conflict resolution" |
| MCP command missing | "MCP slash commands", "dynamic discovery" |
| MCP permission denied | "MCP permissions wildcards", "mcp__servername" |

## Repository-Specific Notes

This repository has custom slash commands stored in `.claude/commands/`.

**Discovery:**

- Use `/help` to see all available commands (built-in + custom)
- Use `/list-commands` for formatted listing of custom commands only
- Browse `.claude/commands/` directly to see command source files

**Notable commands include:** `/commit`, `/lint-md`, `/audit-skills`, `/scrape-official-docs`, `/list-skills`, `/list-commands`, and various `speckit.*` workflow commands.

## Repository Naming Convention

This repository uses a hybrid naming approach for slash commands:

### 1. Dot-Namespacing for Command Families

Use `{domain}.{action}` pattern when creating 2+ related commands in the same domain:

| Domain | Purpose | Examples |
| ------ | ------- | -------- |
| `check.*` | Verification/validation checks | `/check.temp`, `/check.paths`, `/check.duplication`, `/check.guide` |
| `docs.*` | Documentation management | `/docs.refresh`, `/docs.validate` |
| `skill.*` | Skill management | `/skill.create`, `/skill.audit-log` |
| `speckit.*` | Spec workflows (existing) | `/speckit.analyze`, `/speckit.plan`, `/speckit.specify` |
| `agent.*` | Agent workflows | `/agent.handoff` |

### 2. Flat Kebab-Case for Standalone Commands

Use simple kebab-case for single-purpose commands without siblings:

- `/commit` - Git commit workflow
- `/lint-md` - Markdown linting
- `/utc` - Get UTC timestamp

### 3. Rationale

**Why dot-namespacing over subdirectories:**

- **Tab-completion grouping**: Type `/check.` to see all check commands
- **Self-documenting**: Namespace indicates domain ownership
- **Established pattern**: Aligns with existing `speckit.*` commands in this repo
- **Discoverability**: Subdirectories don't change command names (they only add context in `/help`)

**When to create a new family:**

- Creating 2+ related commands in the same domain
- Commands share a common purpose or workflow area
- Commands would logically group together for discoverability

**When to use standalone:**

- Single-purpose utility with no planned siblings
- Simple command that doesn't fit existing families
- Command purpose is immediately clear without namespace

### 4. File Naming

Command files use the exact command name with `.md` extension:

- `/check.temp` -> `.claude/commands/check.temp.md`
- `/commit` -> `.claude/commands/commit.md`
- `/speckit.analyze` -> `.claude/commands/speckit.analyze.md`

## References

**Official Documentation (via docs-management skill):**

- Primary: "slash-commands" documentation
- Related: "skills", "plugins", "MCP", "interactive-mode"

**Repository-Specific:**

- Custom commands: `.claude/commands/`
- Skills for complex workflows: `.claude/skills/`

## Version History

- **v1.0.2** (2025-11-27): Added Repository Naming Convention
  - Added comprehensive naming convention section
  - Documented dot-namespacing for command families
  - Documented flat kebab-case for standalone commands
  - Added rationale and decision guidance
  - Added file naming examples
- **v1.0.1** (2025-11-27): Audit and enhancement
  - Updated Repository-Specific Notes to use folder reference pattern
  - Added MCP permissions wildcards keywords
  - Added character budget keywords
  - Added MCP permissions decision path to quick decision tree
  - Added MCP permission denied troubleshooting entry
  - Referenced new `/list-commands` command for dynamic command discovery
- **v1.0.0** (2025-11-26): Initial release
  - Pure delegation architecture
  - Comprehensive keyword registry
  - Quick decision tree
  - Topic coverage for all slash command features
  - Troubleshooting quick reference

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
