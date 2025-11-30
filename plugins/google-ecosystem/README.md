# Google Ecosystem Plugin

Comprehensive Google Gemini CLI ecosystem plugin for Claude Code. Provides official documentation management, Claude-to-Gemini integration agents, meta-skills for Gemini CLI configuration, and quick integration commands.

## Philosophy: Claude Orchestrates, Gemini Executes

This plugin enables Claude to delegate tasks to Gemini CLI where Gemini excels:

- **Sandbox Isolation**: Execute risky commands safely
- **Checkpointing**: Experimental refactors with instant rollback
- **Large Context**: Analyze 100K+ token codebases (Gemini has 1M+ context)
- **Interactive Shells**: Handle TUI commands (vim, git rebase -i)
- **Second Opinions**: Independent validation from another AI

## Skills (13)

### Documentation

| Skill | Purpose |
|-------|---------|
| `gemini-cli-docs` | Core documentation skill - search, resolve, query official docs |
| `gemini-cli-execution` | Execute Gemini CLI in headless/automation modes |

### Integration

| Skill | Purpose |
|-------|---------|
| `gemini-delegation-patterns` | Decision criteria for when/how to delegate to Gemini |
| `gemini-json-parsing` | Parse JSON/stream-JSON output from Gemini CLI |
| `gemini-token-optimization` | Optimize costs with caching, batching, model selection |

### Management

| Skill | Purpose |
|-------|---------|
| `gemini-command-development` | Create custom TOML commands |
| `gemini-config-management` | Configure settings.json, policies, themes |
| `gemini-checkpoint-management` | Git-based snapshots and /restore rollback |
| `gemini-sandbox-configuration` | Docker/Podman/Seatbelt isolation setup |
| `gemini-session-management` | Session resume, retention, cleanup |

### Development

| Skill | Purpose |
|-------|---------|
| `gemini-extension-development` | Build Gemini CLI extensions |
| `gemini-mcp-integration` | Model Context Protocol server integration |
| `gemini-context-bridge` | CLAUDE.md to GEMINI.md context synchronization |

## Agents (7)

### Documentation

| Agent | Model | Purpose |
|-------|-------|---------|
| `gemini-docs-researcher` | haiku | Research Gemini CLI documentation |
| `gemini-planner` | sonnet | Second-brain planning via Gemini CLI |

### Integration

| Agent | Model | Purpose |
|-------|-------|---------|
| `gemini-sandboxed-executor` | sonnet | Execute risky commands in sandbox |
| `gemini-checkpoint-experimenter` | sonnet | Experimental refactors with rollback |
| `gemini-bulk-analyzer` | haiku | Analyze large codebases (1M+ tokens) |
| `gemini-interactive-shell` | sonnet | Handle TUI commands (vim, rebase) |
| `gemini-second-opinion` | haiku | Independent validation and alternatives |

## Commands (9)

### Documentation

| Command | Purpose |
|---------|---------|
| `/scrape-docs` | Scrape docs from geminicli.com |
| `/refresh-docs` | Rebuild index without scraping |
| `/validate-docs` | Validate index integrity |

### Integration

| Command | Purpose |
|---------|---------|
| `/gemini-query <prompt>` | Quick headless query |
| `/gemini-analyze <file> [type]` | File analysis (security, performance, etc.) |
| `/gemini-second-opinion [topic]` | Get Gemini's perspective |
| `/gemini-sandbox <command>` | Execute in sandbox |

### Discovery

| Command | Purpose |
|---------|---------|
| `/list-skills` | List all skills |
| `/list-commands` | List all commands |

## Installation

```bash
/plugin install google-ecosystem@claude-code-plugins
```

## Quick Start

### Get a Second Opinion

```text
/google-ecosystem:gemini-second-opinion Is this architecture correct?
```

### Analyze Code Securely

```text
/google-ecosystem:gemini-analyze src/auth.ts security
```

### Execute Risky Command Safely

```text
/google-ecosystem:gemini-sandbox npm install unknown-package
```

### Quick Query

```text
/google-ecosystem:gemini-query Explain async/await in JavaScript
```

## Architecture

### Pure Delegation

All meta-skills delegate to `gemini-cli-docs` for official documentation:

```text
gemini-checkpoint-management
        │
        ▼
    gemini-cli-docs ──► canonical/ (scraped docs)
        │
        ▼
    Official Gemini CLI Documentation
```

### Hook Detection

The plugin includes hooks that detect Gemini CLI questions and suggest the appropriate skill:

- High-confidence triggers: `gemini-cli`, `geminicli.com`, `memport`, `policy-engine`
- Context-aware triggers: `checkpointing`, `extensions`, `MCP` (when Gemini context exists)

## Version

**v1.1.0** - Integration-first expansion with 5 delegation agents, 4 integration commands, 6 new skills.

## Related

- [Gemini CLI Documentation](https://geminicli.com)
- [claude-ecosystem plugin](../claude-ecosystem) - Claude Code documentation and meta-skills
