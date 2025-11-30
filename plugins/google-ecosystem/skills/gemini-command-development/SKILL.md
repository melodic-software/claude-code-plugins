---
name: gemini-command-development
description: Expert guide for creating custom Gemini CLI commands. Covers slash command definitions (.toml), argument parsing, and shell execution within commands. Delegates to gemini-cli-docs.
allowed-tools: Read, Glob, Grep, Skill
---

# Gemini Command Development

## 🚨 MANDATORY: Invoke gemini-cli-docs First

> **STOP - Before providing ANY response about Gemini Commands:**
>
> 1. **INVOKE** `gemini-cli-docs` skill
> 2. **QUERY** for the specific command topic
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded

## Overview

Expert skill for defining custom slash commands in the Gemini CLI. Unlike Claude Code's markdown-based commands, Gemini uses **TOML** configuration or **Extension**-based commands.

## When to Use This Skill

**Keywords:** gemini commands, custom slash commands, .toml commands, command arguments, command alias

**Use this skill when:**

- Creating custom commands in `commands.toml` (or similar)
- creating extension-based commands (`<extension>/commands/*.toml`)
- Defining command arguments and defaults
- Mapping commands to complex prompts

## Command Structure (TOML)

Gemini commands are typically defined in TOML files within extensions or configuration.

```toml
[command-name]
description = "Description"
prompt = "The actual prompt to send..."
```

*(Note: Verify exact syntax via `gemini-cli-docs` as specific implementation details vary by version)*

## Keyword Registry (Delegates to gemini-cli-docs)

| Topic | Query Keywords |
| :--- | :--- |
| **Definition** | `custom commands toml`, `define slash command` |
| **Arguments** | `command arguments`, `command variables` |
| **Scope** | `workspace commands`, `global commands` |

## Quick Decision Tree

**What do you want to do?**

1. **Create a Simple Alias** -> Query `gemini-cli-docs`: "create custom command"
2. **Package Command in Extension** -> Query `gemini-cli-docs`: "extension commands structure"

## References

**Official Documentation:**
Query `gemini-cli-docs` for:

- "custom commands"
- "slash commands"
