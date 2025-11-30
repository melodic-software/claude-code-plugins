# Claude Ecosystem Plugin

Meta-skills for Claude Code documentation and ecosystem features. Provides keyword registries, navigation hubs, and decision trees for efficient documentation access.

## Skills Included

All meta-skills delegate to the `official-docs` skill for authoritative documentation content.

| Skill | Purpose |
|-------|---------|
| `agent-sdk-meta` | Claude Agent SDK (TypeScript/Python SDKs, sessions, tools, permissions) |
| `configuration-meta` | Settings and configuration (settings.json, permissions, sandbox, enterprise) |
| `hooks-meta` | Hook events and configuration (PreToolUse, PostToolUse, matchers, validation) |
| `mcp-meta` | Model Context Protocol (MCP servers, transports, resources, authentication) |
| `memory-meta` | CLAUDE.md and memory system (hierarchy, import syntax, progressive disclosure) |
| `output-styles-meta` | Output styles (built-in styles, custom styles, frontmatter, switching) |
| `plugins-meta` | Plugin system (structure, manifest, components, marketplaces, distribution) |
| `security-meta` | Security and sandboxing (permissions, IAM, credential management, enterprise) |
| `skills-meta` | Skill creation and management (templates, validation, YAML frontmatter) |
| `slash-commands-meta` | Slash commands (built-in, custom, plugin, arguments, bash execution) |
| `status-line-meta` | Status line configuration (custom status lines, JSON input, scripts) |
| `subagents-meta` | Subagents and Task tool (agent files, tool access, model selection, lifecycle) |

## Installation

```bash
/plugin install claude-ecosystem@claude-code-plugins
```

## Prerequisites

This plugin requires the `official-docs` plugin to be installed for full functionality:

```bash
/plugin install official-docs@claude-code-plugins
```

## Usage

Meta-skills are automatically invoked by Claude when you ask questions about Claude Code topics. You can also invoke them directly:

```bash
# Invoke a meta-skill for topic guidance
skill: hooks-meta
skill: memory-meta
skill: skills-meta
```

## Architecture

All meta-skills follow a **pure delegation architecture**:

1. **SKILL.md** provides keyword registries and navigation
2. **official-docs** skill provides authoritative documentation content
3. Meta-skills do NOT duplicate official documentation

## Version

- **v1.0.0** (2025-11-30): Initial release - migrated from onboarding repository
