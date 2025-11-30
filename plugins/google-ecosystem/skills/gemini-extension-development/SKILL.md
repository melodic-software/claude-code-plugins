---
name: gemini-extension-development
description: Expert guide for building and managing Gemini CLI Extensions. Covers extension anatomy (context, commands, MCP), development workflow (link, install), and publishing. Delegates to gemini-cli-docs.
allowed-tools: Read, Glob, Grep, Skill
---

# Gemini Extension Development

## 🚨 MANDATORY: Invoke gemini-cli-docs First

> **STOP - Before providing ANY response about Gemini Extensions:**
>
> 1. **INVOKE** `gemini-cli-docs` skill
> 2. **QUERY** for the specific extension topic
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded

## Overview

Expert skill for creating, testing, and distributing Gemini CLI Extensions. Extensions are the primary plugin mechanism for Gemini.

## When to Use This Skill

**Keywords:** gemini extension, create extension, gemini extensions link, extension gallery, context files, extension commands, extension releasing, uninstall extension

**Use this skill when:**

- Creating a new extension (`gemini extensions create`)
- Linking a local extension for development (`gemini extensions link`)
- Packaging MCP servers into extensions
- Adding custom slash commands (`.toml`) to extensions
- Installing extensions from GitHub or local paths
- Releasing extensions via Git or GitHub Releases

## Extension Anatomy

An extension can contain:

1.  **`extension.yaml`:** Manifest file.
2.  **`GEMINI.md`:** Context "playbook" for the model.
3.  **`package.json`:** Dependencies (if using Node.js/TypeScript). **Note:** Use the Unified Google Gen AI SDK (e.g., `google-genai`) as `google-generativeai` is deprecated.
4.  **MCP Servers:** Embedded tools.
5.  **Commands:** `*.toml` files defining custom slash commands.
6.  **Tool Restrictions:** `excludeTools` configuration.

## Development Workflow

1.  **Create:** `gemini extensions create my-extension`
2.  **Link:** `cd my-extension && gemini extensions link .` (Enables hot-reloading)
3.  **Test:** Run `gemini` and use the new capabilities.
4.  **Publish:** Push to GitHub (installable via URL).

## Keyword Registry (Delegates to gemini-cli-docs)

| Topic | Query Keywords |
| :--- | :--- |
| **Creation** | `create extension`, `extension template` |
| **Manifest** | `extension.yaml schema`, `extension manifest` |
| **Commands** | `extension slash commands`, `toml commands` |
| **Linking** | `gemini extensions link`, `local extension dev` |
| **Releasing** | `extension releasing git`, `github release extension` |
| **Management** | `uninstall extension`, `update extension` |

## Quick Decision Tree

**What do you want to do?**

1.  **Start a New Extension** -> Query `gemini-cli-docs`: "create extension boilerplate"
2.  **Test Locally** -> Query `gemini-cli-docs`: "link local extension"
3.  **Add a Command** -> Query `gemini-cli-docs`: "define command in extension"
4.  **Bundle an MCP Server** -> Query `gemini-cli-docs`: "extension mcp server"
5.  **Install an Extension** -> Query `gemini-cli-docs`: "install extension from url"
6.  **Release an Extension** -> Query `gemini-cli-docs`: "extension releasing git vs github"

## References

**Official Documentation:**
Query `gemini-cli-docs` for:
- "extensions"
- "extension development"
