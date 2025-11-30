---
name: mcp-integration
description: Central authority for Claude Code Model Context Protocol (MCP) integration. Covers MCP server installation (HTTP, SSE, stdio transports), server management (add, list, remove), installation scopes (local, project, user), plugin-provided MCP servers, enterprise MCP configuration, MCP resources and @ mentions, MCP prompts as slash commands, OAuth authentication, environment variable expansion, Claude Code as MCP server, output limits, and MCP security. Assists with connecting external tools, configuring MCP servers, managing authentication, and troubleshooting MCP issues. Delegates 100% to docs-management skill for official documentation.
allowed-tools: Read, Glob, Grep, Skill
---

# MCP Meta Skill

## 🚨 MANDATORY: Invoke docs-management First

> **STOP - Before providing ANY response about MCP (Model Context Protocol):**
>
> 1. **INVOKE** `docs-management` skill
> 2. **QUERY** for the user's specific topic
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded
>
> **Skipping this step results in outdated or incorrect information.**

### Verification Checkpoint

Before responding, verify:

- [ ] Did I invoke docs-management skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

If ANY checkbox is unchecked, STOP and invoke docs-management first.

---

## Overview

Central authority for Claude Code Model Context Protocol (MCP) integration. This skill uses **100% delegation to docs-management** - it contains NO duplicated official documentation.

**Architecture:** Pure delegation with keyword registry. All official documentation is accessed via docs-management skill queries.

## When to Use This Skill

**Keywords:** MCP, Model Context Protocol, MCP servers, MCP tools, MCP resources, MCP prompts, HTTP transport, SSE transport, stdio transport, MCP installation, MCP scopes, local scope, project scope, user scope, .mcp.json, plugin MCP servers, enterprise MCP, managed-mcp.json, OAuth authentication, MCP resources, @ mentions, mcp__server__prompt, MCP output limits, MAX_MCP_OUTPUT_TOKENS, claude mcp serve

**Use this skill when:**

- Installing or configuring MCP servers
- Understanding MCP transport types (HTTP, SSE, stdio)
- Managing MCP server scopes (local, project, user)
- Working with plugin-provided MCP servers
- Setting up enterprise MCP configurations
- Using MCP resources with @ mentions
- Executing MCP prompts as slash commands
- Authenticating with remote MCP servers (OAuth)
- Configuring environment variable expansion in .mcp.json
- Using Claude Code as an MCP server
- Managing MCP output limits
- Troubleshooting MCP connection issues

## Keyword Registry for docs-management Queries

Use these keywords when querying docs-management skill for official documentation:

### Core Concepts

| Topic | Keywords |
| ----- | -------- |
| Overview | "MCP", "Model Context Protocol", "MCP overview" |
| What MCP Does | "what you can do with MCP", "MCP capabilities" |
| Popular Servers | "popular MCP servers", "MCP servers table" |

### Installation and Transport

| Topic | Keywords |
| ----- | -------- |
| Installation Overview | "installing MCP servers", "MCP server configuration" |
| HTTP Transport | "HTTP transport MCP", "remote HTTP server", "--transport http" |
| SSE Transport | "SSE transport MCP", "Server-Sent Events transport" |
| Stdio Transport | "stdio transport MCP", "local stdio server" |
| Windows Setup | "Windows MCP servers", "cmd /c npx" |

### Server Management

| Topic | Keywords |
| ----- | -------- |
| Commands | "claude mcp add", "claude mcp list", "claude mcp remove", "/mcp command" |
| JSON Configuration | "add-json MCP", "MCP JSON configuration" |
| Import from Desktop | "add-from-claude-desktop", "import MCP servers" |

### Installation Scopes

| Topic | Keywords |
| ----- | -------- |
| Scope Overview | "MCP installation scopes", "MCP scope levels" |
| Local Scope | "local scope MCP", "project-specific user settings" |
| Project Scope | "project scope MCP", ".mcp.json file" |
| User Scope | "user scope MCP", "cross-project MCP" |
| Scope Precedence | "MCP scope precedence", "scope hierarchy" |

### Plugin Integration

| Topic | Keywords |
| ----- | -------- |
| Plugin MCP Servers | "plugin-provided MCP servers", "plugin MCP configuration" |
| Plugin Features | "CLAUDE_PLUGIN_ROOT", "plugin MCP lifecycle" |

### Enterprise Configuration

| Topic | Keywords |
| ----- | -------- |
| Enterprise Setup | "enterprise MCP configuration", "managed-mcp.json" |
| Allowlists/Denylists | "allowedMcpServers", "deniedMcpServers", "MCP restrictions" |
| Enterprise Paths | "enterprise MCP paths", "managed MCP locations" |

### Resources and Prompts

| Topic | Keywords |
| ----- | -------- |
| MCP Resources | "MCP resources", "@ mentions MCP", "reference MCP resources" |
| MCP Prompts | "MCP prompts", "mcp__servername__promptname", "MCP slash commands" |

### Authentication

| Topic | Keywords |
| ----- | -------- |
| OAuth Setup | "MCP OAuth", "authenticate remote MCP", "/mcp authentication" |
| Token Management | "MCP token refresh", "clear MCP authentication" |

### Advanced Configuration

| Topic | Keywords |
| ----- | -------- |
| Environment Variables | "environment variable expansion", ".mcp.json variables", "${VAR}" |
| Output Limits | "MCP output limits", "MAX_MCP_OUTPUT_TOKENS", "output warning" |
| Claude as Server | "claude mcp serve", "Claude Code as MCP server" |

### Security

| Topic | Keywords |
| ----- | -------- |
| MCP Security | "MCP security", "MCP prompt injection", "trust MCP servers" |

## Quick Decision Tree

**What do you want to do?**

1. **Add a remote MCP server** -> Query docs-management: "installing MCP servers", "HTTP transport MCP"
2. **Add a local MCP server** -> Query docs-management: "stdio transport MCP", "local stdio server"
3. **Understand scopes** -> Query docs-management: "MCP installation scopes", "scope precedence"
4. **Share MCP with team** -> Query docs-management: "project scope MCP", ".mcp.json file"
5. **Use MCP across projects** -> Query docs-management: "user scope MCP", "cross-project MCP"
6. **Configure plugin MCP** -> Query docs-management: "plugin-provided MCP servers"
7. **Set up enterprise MCP** -> Query docs-management: "enterprise MCP configuration", "managed-mcp.json"
8. **Authenticate with OAuth** -> Query docs-management: "MCP OAuth", "/mcp authentication"
9. **Reference MCP resources** -> Query docs-management: "MCP resources", "@ mentions MCP"
10. **Use MCP prompts** -> Query docs-management: "MCP prompts", "MCP slash commands"
11. **Expose Claude as MCP server** -> Query docs-management: "claude mcp serve"
12. **Troubleshoot MCP issues** -> Query docs-management: "MCP troubleshooting" + specific issue

## Topic Coverage

### Transport Types and Installation

- HTTP transport (recommended for remote servers)
- SSE transport (deprecated, use HTTP)
- Stdio transport (local processes)
- Windows-specific setup (cmd /c wrapper)
- Double dash (--) parameter explanation
- MCP_TIMEOUT environment variable

### Server Management Commands

- `claude mcp add` (with transport flags)
- `claude mcp list` (show all servers)
- `claude mcp get` (server details)
- `claude mcp remove` (delete server)
- `/mcp` command (in-session status)
- `claude mcp add-json` (JSON configuration)
- `claude mcp add-from-claude-desktop` (import)
- `claude mcp reset-project-choices` (approval reset)

### Scope Configuration

- Local scope (default, private to user/project)
- Project scope (.mcp.json, version controlled)
- User scope (cross-project, private)
- Scope precedence (local > project > user)
- --scope flag usage

### Environment Variable Expansion

- ${VAR} syntax
- ${VAR:-default} syntax with defaults
- Supported expansion locations (command, args, env, url, headers)
- Missing variable handling

### Plugin MCP Server Integration

- Plugin .mcp.json configuration
- Inline mcpServers in plugin.json
- CLAUDE_PLUGIN_ROOT variable
- Automatic lifecycle management
- Multiple transport type support

### Enterprise MCP Management

- managed-mcp.json file locations (macOS, Windows, Linux)
- allowedMcpServers configuration
- deniedMcpServers configuration
- Allowlist/denylist precedence
- Enterprise scope precedence

### MCP Resources System

- @ mention syntax for resources
- Resource path format (@server:protocol://path)
- Multiple resource references
- Fuzzy search in autocomplete
- Resource content types

### MCP Prompts as Commands

- /mcp__servername__promptname format
- Executing prompts with arguments
- Dynamic discovery from servers
- Name normalization (spaces to underscores)

### Authentication Mechanisms

- OAuth 2.0 support
- /mcp command for authentication
- Token storage and refresh
- Clear authentication option
- HTTP server authentication

### Output Limits and Configuration

- Default 25,000 token limit
- Warning at 10,000 tokens
- MAX_MCP_OUTPUT_TOKENS configuration
- Use cases for higher limits

### Claude Code as MCP Server

- `claude mcp serve` command
- Claude Desktop integration
- Configuration format
- Exposed tools (View, Edit, LS, etc.)
- Executable path configuration

## Delegation Patterns

### Standard Query Pattern

```text
User asks: "How do I add an MCP server?"

1. Invoke docs-management skill
2. Use keywords: "installing MCP servers", "claude mcp add"
3. Load official documentation
4. Provide guidance based EXCLUSIVELY on official docs
```

### Multi-Topic Query Pattern

```text
User asks: "I want to share MCP servers with my team and authenticate with OAuth"

1. Invoke docs-management skill with multiple queries:
   - "project scope MCP", ".mcp.json file"
   - "MCP OAuth", "/mcp authentication"
2. Synthesize guidance from official documentation
```

### Troubleshooting Pattern

```text
User reports: "My MCP server won't connect on Windows"

1. Invoke docs-management skill
2. Use keywords: "Windows MCP servers", "cmd /c npx"
3. Check official docs for Windows-specific requirements
4. Guide user through Windows setup from official docs
```

## Troubleshooting Quick Reference

| Issue | Keywords for docs-management |
| ----- | ------------------------ |
| Server won't connect | "installing MCP servers", specific transport type |
| Windows connection errors | "Windows MCP servers", "cmd /c" |
| Authentication failing | "MCP OAuth", "/mcp authentication" |
| Scope not working | "MCP installation scopes", "scope precedence" |
| Environment variables not expanding | "environment variable expansion", ".mcp.json variables" |
| Output too large | "MCP output limits", "MAX_MCP_OUTPUT_TOKENS" |
| Plugin MCP not loading | "plugin-provided MCP servers", "plugin MCP lifecycle" |
| Enterprise restrictions | "allowedMcpServers", "deniedMcpServers" |

## Repository-Specific Notes

This repository uses MCP servers for:

- **context7 MCP**: Library documentation lookup
- **firecrawl MCP**: Web scraping and search
- **microsoft-learn MCP**: Microsoft/Azure documentation
- **perplexity MCP**: AI-powered search
- **Ref MCP**: Documentation reference lookup

MCP servers are configured in the project's settings and should follow the patterns documented in official Claude Code documentation.

## References

**Official Documentation (via docs-management skill):**

- Primary: "mcp" documentation
- Related: "plugins", "hooks", "settings", "security"

**Repository-Specific:**

- MCP configuration: Project-level .mcp.json or local settings
- Skills configuration: `.claude/settings.json`

## Version History

- **v1.0.0** (2025-11-26): Initial release
  - Pure delegation architecture
  - Comprehensive keyword registry
  - Quick decision tree
  - Topic coverage for all MCP features
  - Troubleshooting quick reference

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
