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

## Plugin Commands (claude-ecosystem)

This plugin provides slash commands in `plugins/claude-ecosystem/commands/`:

- `/claude-ecosystem:scrape-docs` - Scrape Claude documentation from official sources
- `/claude-ecosystem:refresh-docs` - Refresh local index without network scraping
- `/claude-ecosystem:validate-docs` - Validate index integrity and detect drift

**Discovery:**

- Use `/help` to see all available commands (built-in + plugin)
- Plugin commands can be invoked with or without the `claude-ecosystem:` prefix (when no conflicts)

## Naming Conventions

### Official Patterns (from Built-in Commands)

Claude Code's built-in commands use these patterns:

| Pattern | Use Case | Examples |
| ------- | -------- | -------- |
| **Verb-noun kebab-case** | Action commands | `/add-dir`, `/release-notes`, `/security-review` |
| **Single noun** | State/display commands | `/status`, `/permissions`, `/config`, `/cost` |
| **Single verb** | Simple actions | `/clear`, `/exit`, `/login`, `/resume` |

**Key insight:** Built-in commands do NOT use dot-namespacing or noun-first grouping.

### Recommended Approach

**For action commands (scrape, refresh, validate, create, etc.):**

Use **verb-noun kebab-case**: `/scrape-docs`, `/refresh-docs`, `/validate-docs`

**For display/status commands (built-in examples):**

Use **single noun**: `/status`, `/config`, `/todos`

**For simple utilities (built-in examples):**

Use **single verb or short descriptive name**: `/clear`, `/compact`, `/review`

### Plugin Command Namespacing

Plugin commands get automatic namespacing via `/plugin-name:command`:

- `/claude-ecosystem:scrape-docs` (fully qualified)
- `/scrape-docs` (short form when no conflicts)

This means you don't need to embed the domain in the command name—the plugin prefix handles disambiguation.

### File Naming

Command files use the exact command name with `.md` extension:

- `/scrape-docs` -> `commands/scrape-docs.md`
- `/refresh-docs` -> `commands/refresh-docs.md`
- `/validate-docs` -> `commands/validate-docs.md`

## Auditing Commands

This skill provides the validation criteria used by the `command-auditor` agent for formal audits.

### Audit Resources

| Resource | Location | Purpose |
| -------- | -------- | ------- |
| Validation Checklist | `references/validation-checklist.md` | Pre-creation verification checklist |
| Scoring Rubric | `references/validation-checklist.md#audit-scoring-rubric` | Formal audit scoring criteria |

### Scoring Categories

| Category | Points | Key Criteria |
| -------- | ------ | ------------ |
| File Structure | 20 | Correct location, .md extension, kebab-case naming |
| YAML Frontmatter | 25 | Description, allowed-tools, argument-hint present |
| Description Quality | 20 | Clear, concise, action-oriented, when-to-use guidance |
| Tool Configuration | 15 | Not over/under restricted for purpose |
| Content Quality | 20 | Well-structured, proper argument handling, file references |

**Thresholds:** 85+ = PASS, 70-84 = PASS WITH WARNINGS, <70 = FAIL

### Related Agent

The `command-auditor` agent (Haiku model) performs formal audits using this skill:

- Auto-loads this skill via `skills: command-development`
- Uses validation checklist and scoring rubric
- Generates structured audit reports
- Invoked by `/audit-commands` command

## References

**Official Documentation (via docs-management skill):**

- Primary: "slash-commands" documentation
- Related: "skills", "plugins", "MCP", "interactive-mode"

**This Plugin:**

- Plugin commands: `plugins/claude-ecosystem/commands/`
- Plugin skills: `plugins/claude-ecosystem/skills/`

## Version History

- **v1.0.3** (2025-11-30): Revised naming conventions based on official docs analysis
  - Updated naming conventions to align with built-in command patterns
  - Recommended verb-noun kebab-case for action commands
  - Removed dot-namespacing recommendation (not used by built-in commands)
  - Documented plugin command automatic namespacing
- **v1.0.2** (2025-11-27): Added Repository Naming Convention
  - Added comprehensive naming convention section
  - Documented dot-namespacing for command families
  - Documented flat kebab-case for standalone commands
  - Added rationale and decision guidance
  - Added file naming examples
- **v1.0.1** (2025-11-27): Audit and enhancement
  - Added MCP permissions wildcards keywords
  - Added character budget keywords
  - Added MCP permissions decision path to quick decision tree
  - Added MCP permission denied troubleshooting entry
- **v1.0.0** (2025-11-26): Initial release
  - Pure delegation architecture
  - Comprehensive keyword registry
  - Quick decision tree
  - Topic coverage for all slash command features
  - Troubleshooting quick reference

---

## Last Updated

**Date:** 2025-11-30
**Model:** claude-opus-4-5-20251101
