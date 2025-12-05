# Claude Code Plugin Guide

This document contains comprehensive knowledge about Claude Code plugins, sourced from official documentation. Use this as a reference when creating, auditing, or modifying plugins.

---

## Table of Contents

1. [Plugin Structure](#plugin-structure)
2. [Plugin Manifest (plugin.json)](#plugin-manifest-pluginjson)
3. [Marketplace Configuration (marketplace.json)](#marketplace-configuration-marketplacejson)
4. [Plugin Components](#plugin-components)
5. [Best Practices](#best-practices)
6. [This Repository's Plugins](#this-repositorys-plugins)

---

## Plugin Structure

### Required Directory Layout

```text
my-plugin/
├── .claude-plugin/           # REQUIRED: Metadata directory
│   └── plugin.json          # REQUIRED: Plugin manifest
├── commands/                 # Optional: Slash command markdown files
├── agents/                   # Optional: Subagent markdown files
├── skills/                   # Optional: Agent Skills with SKILL.md files
├── hooks/                    # Optional: Hook configuration
│   └── hooks.json
├── .mcp.json                # Optional: MCP server definitions
├── scripts/                 # Optional: Utility scripts
├── LICENSE                  # Recommended
├── CHANGELOG.md             # Recommended
└── README.md                # Recommended
```

### Critical Rules

1. **`.claude-plugin/` contains ONLY `plugin.json`** - All component directories (commands/, agents/, skills/, hooks/) must be at the plugin root, NOT inside `.claude-plugin/`
2. **All paths must be relative** - Start with `./` and be relative to the plugin root
3. **Use `${CLAUDE_PLUGIN_ROOT}`** - Environment variable containing absolute path to plugin directory, use in hooks and MCP servers

---

## Plugin Manifest (plugin.json)

Located at `.claude-plugin/plugin.json` within the plugin root.

### Complete Schema

```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "Brief plugin description",
  "author": {
    "name": "Author Name",
    "email": "author@example.com",
    "url": "https://github.com/author"
  },
  "homepage": "https://docs.example.com/plugin",
  "repository": "https://github.com/author/plugin",
  "license": "MIT",
  "keywords": ["keyword1", "keyword2"],
  "commands": "./commands",
  "agents": ["./agents/agent1.md", "./agents/agent2.md"],
  "skills": "./skills",
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json"
}
```

### Field Reference

| Field | Type | Required | Description |
| ------- | ------ | ---------- | ------------- |
| `name` | string | **Yes** | Unique identifier (kebab-case, no spaces) |
| `version` | string | No | Semantic version (e.g., "1.0.0") |
| `description` | string | No | Brief explanation of plugin purpose |
| `author` | object | No | Author info: `{name, email?, url?}` |
| `homepage` | string | No | Documentation URL |
| `repository` | string | No | Source code URL |
| `license` | string | No | License identifier (e.g., "MIT") |
| `keywords` | array | No | Discovery tags |
| `commands` | string\|array | No | Command files/directories |
| `agents` | string\|array | No | Agent files/directories |
| `skills` | string | No | Skills directory (default: `./skills`) |
| `hooks` | string\|object | No | Hook config path or inline config |
| `mcpServers` | string\|object | No | MCP config path or inline config |

### Notes

- Only `name` is strictly required
- Custom paths SUPPLEMENT default directories (don't replace them)
- Skills use default `skills/` directory - no custom path field documented

### Critical Validation Rules (Learned from Runtime)

1. **`agents` field MUST use explicit `.md` file paths** - Directory paths like `"./agents"` will fail validation with error: "agents: Invalid input: must end with .md". Always use array format: `["./agents/agent1.md", "./agents/agent2.md"]`

2. **Do NOT declare `hooks` if using default `hooks/hooks.json`** - The standard `hooks/hooks.json` is auto-loaded by convention. Explicitly declaring it causes: "Duplicate hooks file detected". Only use the `hooks` field for ADDITIONAL hook files beyond the default.

3. **`commands` and `skills` CAN use directory paths** - These fields accept both directory paths (`"./commands"`) and explicit file arrays

---

## Marketplace Configuration (marketplace.json)

Located at `.claude-plugin/marketplace.json` in the marketplace root.

### Complete Schema

```json
{
  "name": "marketplace-name",
  "owner": {
    "name": "Owner Name",
    "email": "owner@example.com",
    "url": "https://github.com/owner"
  },
  "metadata": {
    "description": "Marketplace description",
    "version": "1.0.0",
    "pluginRoot": "./plugins"
  },
  "plugins": [
    {
      "name": "plugin-name",
      "source": "./plugins/plugin-name",
      "description": "Plugin description",
      "version": "1.0.0",
      "author": {
        "name": "Author Name",
        "url": "https://github.com/author"
      },
      "license": "MIT",
      "keywords": ["keyword1", "keyword2"]
    }
  ]
}
```

### Required Fields

| Field | Type | Description |
| ------- | ------ | ------------- |
| `name` | string | Marketplace identifier (kebab-case) |
| `owner` | object | Maintainer info: `{name, email?, url?}` |
| `plugins` | array | List of available plugins |

### Plugin Entry Fields

| Field | Required | Description |
| ------- | ---------- | ------------- |
| `name` | **Yes** | Plugin identifier |
| `source` | **Yes** | Path or source object |
| `description` | No | Plugin description |
| `version` | No | Plugin version |
| `author` | No | Plugin author |
| `license` | No | License identifier |
| `keywords` | No | Discovery tags |

### Source Types

**Relative Path:**

```json
{ "source": "./plugins/my-plugin" }
```

**GitHub:**

```json
{ "source": { "source": "github", "repo": "owner/plugin-repo" } }
```

**Git URL:**

```json
{ "source": { "source": "url", "url": "https://gitlab.com/team/plugin.git" } }
```

---

## Plugin Components

### Commands

**Location:** `commands/` directory

**Format:** Markdown files with YAML frontmatter

**Key Frontmatter:**

- `description`: Brief command description
- `allowed-tools`: Tools the command can use
- `argument-hint`: Arguments expected
- `model`: Specific model to use

**Namespacing:** `/plugin-name:command-name`

**Variables:**

- `$ARGUMENTS`: All arguments
- `$1`, `$2`, etc.: Positional arguments

### Skills

**Location:** `skills/skill-name/SKILL.md`

**Structure:**

```text
skills/
└── my-skill/
    ├── SKILL.md (required)
    ├── reference.md (optional)
    └── scripts/ (optional)
```

**Key Frontmatter:**

- `name`: Required, lowercase with hyphens (max 64 chars)
- `description`: Required, what it does and when to use (max 1024 chars)
- `allowed-tools`: Optional, tool restrictions

**Integration:** Model-invoked (Claude decides when to use)

### Agents

**Location:** `agents/` directory

**Format:** Markdown files with YAML frontmatter

**Key Frontmatter:**

- `name`: Required, unique identifier
- `description`: Required, when to invoke
- `tools`: Optional, comma-separated tool list
- `model`: Optional (`sonnet`, `opus`, `haiku`, `inherit`)

**Integration:** Via `/agents` or automatic delegation

### Hooks

**Location:** `hooks/hooks.json`

**Available Events:**

- `PreToolUse`, `PostToolUse`, `PermissionRequest`
- `UserPromptSubmit`, `Stop`, `SubagentStop`
- `SessionStart`, `SessionEnd`, `PreCompact`
- `Notification`

**Hook Types:**

- `type: "command"` - Execute shell commands
- `type: "prompt"` - LLM-based evaluation

### MCP Servers

**Location:** `.mcp.json` at plugin root

**Format:**

```json
{
  "mcpServers": {
    "server-name": {
      "command": "${CLAUDE_PLUGIN_ROOT}/server",
      "args": ["--config", "..."],
      "env": { "KEY": "value" }
    }
  }
}
```

---

## Best Practices

### Naming Conventions

- **Plugin names:** kebab-case, no spaces (e.g., `code-formatter`)
- **Command names:** kebab-case, verb-phrase (e.g., `format-code`)
- **Skill names:** kebab-case, noun-phrase (e.g., `code-formatting`)

### Version Management

Use semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR:** Breaking changes
- **MINOR:** New features (backward compatible)
- **PATCH:** Bug fixes

### Descriptions

- Keep brief and clear
- Focus on what the plugin does
- Use active voice
- Ensure marketplace.json matches plugin.json exactly

### Security

- Use `${CLAUDE_PLUGIN_ROOT}` for all plugin paths
- All paths must be relative
- Test extensively before distribution
- Document security implications
- Make hook scripts executable (`chmod +x`)

### Common Issues

| Issue | Solution |
| ------- | ---------- |
| Plugin not loading | Validate JSON syntax |
| Commands not appearing | Ensure `commands/` at root, not in `.claude-plugin/` |
| Hooks not firing | Run `chmod +x script.sh` |
| Path errors | All paths must be relative, start with `./` |

### Debugging

```bash
claude --debug
```

Shows plugin loading details, errors, and registration status.

---

## This Repository's Plugins

### Plugin Inventory

| Plugin | Version | Description |
| -------- | --------- | ------------- |
| claude-ecosystem | 1.0.0 | Claude Code documentation, meta-skills, observability hooks |
| google-ecosystem | 1.0.0 | Gemini CLI integration, documentation, agents |
| code-quality | 1.0.0 | Code review, debugging, markdown linting |
| git | 1.0.0 | Git configuration, GPG signing, history exploration |
| melodic-software | 1.0.0 | Developer onboarding, environment setup |
| claude-code-observability | 1.0.0 | Event logging, diagnostics (hooks only) |
| windows-diagnostics | 1.0.0 | Windows system troubleshooting |
| tactical-agentic-coding | 1.0.0 | TAC course content by @IndyDevDan |

### Installation

```bash
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install plugin-name@claude-code-plugins
```

### Development

1. Clone repository
2. Make changes to plugin
3. Test with `/plugin marketplace add ./path/to/repo`
4. Validate with `claude --debug`

---

## References

- [Plugins Guide](https://code.claude.com/docs/en/plugins)
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
- [Settings](https://code.claude.com/docs/en/settings)
- [Agent SDK Plugins](https://platform.claude.com/docs/en/agent-sdk/plugins)

---

**Last Updated:** 2025-12-04
