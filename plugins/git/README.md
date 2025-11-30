# Git Plugin

Comprehensive Git workflow toolkit for Claude Code with safety protocols, Conventional Commits format, GPG signing, hooks management, and cross-platform configuration.

## Installation

```bash
/plugin install git@claude-code-plugins
```

Or for local development:

```bash
/plugin install ./plugins/git
```

## Components

### Skills (9)

| Skill | Description |
|-------|-------------|
| `git:git-commit` | Conventional Commits with safety protocols, 4-step workflow |
| `git:git-push` | Push operations with force-push safety (force-with-lease) |
| `git:git-config` | Configuration, aliases, performance tuning, credentials |
| `git:git-gpg-signing` | GPG commit signing setup and troubleshooting |
| `git:git-hooks` | Pre-commit hooks, Husky, lefthook, secret scanning |
| `git:git-line-endings` | Cross-platform line ending configuration |
| `git:git-setup` | Git installation and initial configuration |
| `git:git-gui-tools` | GitKraken, Sourcetree, GitHub Desktop |
| `git:gpg-multi-key` | Advanced multi-key GPG for consultants/CI/enterprise |

### Agent (1)

| Agent | Description |
|-------|-------------|
| `git-operations` | Read-only git operations with smart summaries (diff, status, log, blame, stash) |

### Command (1)

| Command | Description |
|---------|-------------|
| `/git:commit` | Create commits using Conventional Commits format with full safety protocols |

## Usage Examples

### Create a Commit

```text
/git:commit
```

Or invoke the skill directly:

```text
skill: git:git-commit
```

### Git Status Summary

Use the agent for concise summaries:

```text
Use the git-operations agent to summarize the current git status
```

### Configure GPG Signing

```text
skill: git:git-gpg-signing
```

### Set Up Git Hooks

```text
skill: git:git-hooks
```

## Safety Features

The git plugin enforces several safety protocols:

- **No force push to main/master** without explicit confirmation
- **No --no-verify** flag (hooks must run)
- **No --amend** on commits you didn't author
- **Secrets detection** before committing
- **Conventional Commits** format enforcement
- **Attribution footer** on all commits

## Cross-Platform Support

All skills support:

- Windows (Git for Windows, Git Bash)
- macOS (Homebrew, Xcode Command Line Tools)
- Linux (apt, dnf, pacman)
- WSL (Windows Subsystem for Linux)

## Dependencies

- Git 2.35+ (recommended)
- GPG (optional, for signing)
- Bash/PowerShell for command execution

## Related Plugins

- `claude-ecosystem` - Meta-skills and documentation management
- `code-quality` - Code review and linting

## License

MIT
