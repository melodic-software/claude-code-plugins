# Claude Code Plugins

Plugins for Claude Code: documentation management, code quality, and ecosystem support.

## Installation

```bash
/plugin install claude-ecosystem@claude-code-plugins
/plugin install code-quality@claude-code-plugins
/plugin install google-ecosystem@claude-code-plugins
```

## Plugins

| Plugin | Purpose |
|--------|---------|
| [claude-ecosystem](plugins/claude-ecosystem/) | Claude Code docs, meta-skills, hooks |
| [code-quality](plugins/code-quality/) | Code review, linting, debugging |
| [google-ecosystem](plugins/google-ecosystem/) | Gemini CLI docs and planning |

## Discovery

```bash
/claude-ecosystem:list-skills    # List all skills
/claude-ecosystem:list-commands  # List all commands
```

## Architecture

- **Pure delegation**: Skills delegate to `docs-management` for official docs
- **Progressive disclosure**: Content loads on-demand to optimize tokens

See individual plugin READMEs for details.
