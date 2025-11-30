# Code Quality Templates

This directory contains template configuration files for code quality tools. Copy these to your project and customize as needed.

## Markdown Linting Templates

### `.markdownlint-cli2.jsonc`

**Template:** `markdownlint-cli2.jsonc.template`

**Destination:** Project root (`.markdownlint-cli2.jsonc`)

**Purpose:** Single source of truth for markdown linting rules. Used by:

- markdownlint-cli2 CLI (`npx markdownlint-cli2`)
- VS Code markdownlint extension
- GitHub Actions workflow

**Setup:**

```bash
cp markdownlint-cli2.jsonc.template /path/to/project/.markdownlint-cli2.jsonc
```

### GitHub Actions Workflow

**Template:** `github-actions-markdown-lint.yml.template`

**Destination:** `.github/workflows/markdown-lint.yml`

**Purpose:** Automated markdown linting on PRs and main branch pushes.

**Setup:**

```bash
mkdir -p /path/to/project/.github/workflows
cp github-actions-markdown-lint.yml.template /path/to/project/.github/workflows/markdown-lint.yml
```

### VS Code Settings

**Template:** `vscode-settings.json.template`

**Destination:** `.vscode/settings.json`

**Purpose:** Auto-fix on save and editor integration for markdown linting.

**Setup:**

```bash
mkdir -p /path/to/project/.vscode
cp vscode-settings.json.template /path/to/project/.vscode/settings.json
```

**Note:** If `.vscode/settings.json` already exists, merge the settings manually.

## Usage

1. Copy the template file to your project
2. Rename by removing `.template` suffix
3. Review and customize settings for your project
4. Commit the configuration to version control

## Customization

Each template includes comments explaining available options. Common customizations:

- **Rules:** Enable/disable specific markdown rules in `.markdownlint-cli2.jsonc`
- **Ignores:** Add patterns for files/directories to exclude from linting
- **Triggers:** Adjust GitHub Actions triggers for your workflow (branches, paths)
- **Auto-fix:** Enable/disable automatic fixing in VS Code or GitHub Actions

## Related Documentation

- [Installation Setup Guide](../skills/markdown-linting/references/installation-setup.md)
- [Markdownlint Rules Reference](../skills/markdown-linting/references/markdownlint-rules.md)
- [VS Code Extension Setup](../skills/markdown-linting/references/vscode-extension-setup.md)
- [GitHub Actions Configuration](../skills/markdown-linting/references/github-actions-config.md)
