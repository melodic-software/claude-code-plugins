# Claude Ecosystem Plugin

Comprehensive Claude Code ecosystem plugin with official documentation management, meta-skills for all Claude Code features, development guidance, observability hooks, and event logging.

## Features

- **Official Documentation Management**: Keyword-based doc discovery, doc_id resolution, token-optimized subsection extraction
- **Meta-Skills**: Authoritative knowledge hubs for hooks, memory, skills, MCP, configuration, security, subagents, plugins
- **Observability Hooks**: Comprehensive event logging, date/time injection, file validation
- **Utility Skills**: Current date verification, MCP research coordination

## Skills Included

All skills delegate to `docs-management` for authoritative documentation content.

| Skill | Purpose |
| ------- | --------- |
| `agent-sdk-development` | Claude Agent SDK (TypeScript/Python SDKs, sessions, tools, permissions) |
| `command-development` | Slash commands (built-in, custom, plugin, arguments, bash execution) |
| `current-date` | Current UTC date/time verification (prevents stale date assumptions) |
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

## Agents Included

| Agent | Purpose |
| ----- | ------- |
| `docs-researcher` | Research official documentation with keyword-based discovery |
| `skill-auditor` | Audit skills for quality, compliance, and maintainability |
| `mcp-research` | Coordinate queries across multiple MCP servers (context7, ref, microsoft-learn, perplexity, firecrawl) |

## Hooks Included

| Hook | Event | Purpose |
| ---- | ----- | ------- |
| `inject-current-date` | SessionStart | Inject current UTC date/time into Claude's context |
| `log-hook-events` | All events | JSONL logging for observability and debugging |
| `prevent-backup-files` | PreToolUse (Write/Edit) | Block creation of .bak and backup files |
| `suggest-docs-delegation` | UserPromptSubmit | Suggest docs-management skill for Claude Code questions |

## Commands Included

| Command | Purpose |
| ------- | ------- |
| `/claude-ecosystem:audit-log` | View skill audit log entries |
| `/claude-ecosystem:audit-skills` | Audit skills for quality and compliance |
| `/claude-ecosystem:create-skill` | Create new skill scaffold with required structure |
| `/claude-ecosystem:list-commands` | List all custom slash commands |
| `/claude-ecosystem:list-skills` | List all available skills |
| `/claude-ecosystem:refresh-docs` | Refresh docs index without network scraping |
| `/claude-ecosystem:scrape-docs` | Scrape Claude documentation from official sources |
| `/claude-ecosystem:validate-docs` | Validate docs index integrity |

## Installation

```bash
/plugin install claude-ecosystem@claude-code-plugins
```

## Usage

Skills are automatically invoked by Claude when you ask questions about Claude Code topics. You can also invoke them directly:

```bash
# Invoke a skill for topic guidance
skill: claude-ecosystem:hook-management
skill: claude-ecosystem:memory-management
skill: claude-ecosystem:skill-development

# Use commands
/claude-ecosystem:list-skills
/claude-ecosystem:create-skill my-new-skill
```

## Architecture

All skills follow a **pure delegation architecture**:

1. **SKILL.md** provides keyword registries and navigation
2. **docs-management** skill provides authoritative documentation content
3. Skills do NOT duplicate official documentation

## Version

- **v3.0.0** (2025-11-30): Added observability hooks and utility skills
  - Added comprehensive hook event logging (log-hook-events)
  - Added date/time injection (inject-current-date)
  - Added backup file prevention (prevent-backup-files)
  - Added current-date skill for verification
  - Added mcp-research agent for multi-server coordination
  - Added create-skill command
  - Added shared hook utilities (json-utils, path-utils, config-utils, git-utils)

- **v2.0.0** (2025-11-30): Consolidated plugin with noun-phrase naming convention
  - Merged official-docs plugin into claude-ecosystem
  - Renamed all skills to consistent noun-phrase pattern
  - Split security-meta into 3 focused skills (sandbox-configuration, permission-management, enterprise-security)
  - Added validation reference checklists
