# Code Quality Plugin

Code quality tools for Claude Code: markdown linting with auto-fix, validation hooks, and CI/CD templates.

## Installation

```bash
/plugin install code-quality@claude-code-plugins
```

## Features

### Markdown Linting

Automatic markdown linting and auto-fix on file write/edit operations.

**Skill:** `code-quality:markdown-linting`

- Comprehensive markdown linting guidance
- Rule explanations and fixing strategies
- VS Code extension setup
- GitHub Actions integration

**Command:** `/code-quality:lint-md`

- Lint specific files or directories
- Natural language targeting support

**Hook:** PostToolUse (Write|Edit)

- Automatically runs `markdownlint-cli2 --fix` on markdown files
- Warns about unfixable errors
- Configurable enforcement mode via `CLAUDE_HOOK_ENFORCEMENT_MARKDOWN_LINT`

### Configuration Templates

The plugin provides configuration templates in the `templates/` directory:

- `templates/markdownlint-cli2.jsonc.template` - Linting rules configuration
- `templates/vscode-settings.json.template` - VS Code auto-fix on save
- `templates/github-actions-markdown-lint.yml.template` - CI/CD workflow

To customize for your project:

1. Copy the relevant template to your project (remove `.template` suffix)
2. Modify rules and ignores as needed
3. The hook will use your project's `.markdownlint-cli2.jsonc` if present

## Environment Variables

| Variable | Default | Description |
| ---------- | --------- | ------------- |
| `CLAUDE_HOOK_MARKDOWN_LINT_ENABLED` | `0` (disabled) | Set to `1` or `true` to enable the hook |
| `CLAUDE_HOOK_ENFORCEMENT_MARKDOWN_LINT` | `warn` | Enforcement mode: `block`, `warn`, or `log` |
| `CLAUDE_HOOK_LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |

**Note:** The markdown-lint hook is disabled by default because it requires `markdownlint-cli2` to be installed. Enable it explicitly after ensuring the dependency is available.

## Requirements

- `jq` - JSON processor (for hook payload parsing)
- `npx` - For running markdownlint-cli2
- `markdownlint-cli2` - Installed globally or via npx

## Version History

- **1.0.0** - Initial release with markdown-linting skill, command, and hook
