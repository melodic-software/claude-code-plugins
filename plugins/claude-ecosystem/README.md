# Claude Ecosystem Plugin

Comprehensive Claude Code ecosystem plugin with official documentation management, meta-skills for all Claude Code features, and development guidance.

## Skills Included

All skills delegate to `docs-management` for authoritative documentation content.

| Skill | Purpose |
| ------- | --------- |
| `agent-sdk-development` | Claude Agent SDK (TypeScript/Python SDKs, sessions, tools, permissions) |
| `command-development` | Slash commands (built-in, custom, plugin, arguments, bash execution) |
| `docs-management` | Official documentation management (scraping, indexing, discovery, resolution) |
| `enterprise-security` | Enterprise policies (managed-settings.json, precedence, cloud execution) |
| `hook-management` | Hook events and configuration (PreToolUse, PostToolUse, matchers, validation) |
| `mcp-integration` | Model Context Protocol (MCP servers, transports, resources, authentication) |
| `memory-management` | CLAUDE.md and memory system (hierarchy, import syntax, progressive disclosure) |
| `output-customization` | Output styles (built-in styles, custom styles, frontmatter, switching) |
| `permission-management` | Permission rules (allow/deny/ask, tool permissions, wildcards) |
| `plugin-development` | Plugin system (structure, manifest, components, marketplaces, distribution) |
| `sandbox-configuration` | Sandboxing and isolation (filesystem, network, container security) |
| `settings-management` | Settings and configuration (settings.json, permissions, sandbox, enterprise) |
| `skill-development` | Skill creation and management (templates, validation, YAML frontmatter) |
| `status-line-customization` | Status line configuration (custom status lines, JSON input, scripts) |
| `subagent-development` | Subagents and Task tool (agent files, tool access, model selection, lifecycle) |

## Installation

```bash
/plugin install claude-ecosystem@claude-code-plugins
```

## Usage

Skills are automatically invoked by Claude when you ask questions about Claude Code topics. You can also invoke them directly:

```bash
# Invoke a skill for topic guidance
skill: hook-management
skill: memory-management
skill: skill-development
```

## Architecture

All skills follow a **pure delegation architecture**:

1. **SKILL.md** provides keyword registries and navigation
2. **docs-management** skill provides authoritative documentation content
3. Skills do NOT duplicate official documentation

## Version

- **v2.0.0** (2025-11-30): Consolidated plugin with noun-phrase naming convention
  - Merged official-docs plugin into claude-ecosystem
  - Renamed all skills to consistent noun-phrase pattern
  - Split security-meta into 3 focused skills (sandbox-configuration, permission-management, enterprise-security)
  - Added validation reference checklists
