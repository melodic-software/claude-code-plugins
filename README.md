# Claude Code Plugins

Plugins for Claude Code: documentation management, code quality, and ecosystem support.

## Prerequisites

- [Claude Code](https://code.claude.com) installed
- Python 3.12+ (for spaCy-based operations)

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

## Usage

List available skills and commands:

```bash
/claude-ecosystem:list-skills
/claude-ecosystem:list-commands
```

## Architecture

- **Pure delegation**: Skills delegate to `docs-management` for official docs
- **Progressive disclosure**: Content loads on-demand to optimize tokens

See individual plugin READMEs for details.

## License

MIT - see [LICENSE](LICENSE)
