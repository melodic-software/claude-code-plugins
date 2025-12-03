# Git Plugin

Git configuration, GPG signing, hooks management, cross-platform setup, and read-only history exploration agent.

## Installation

```bash
/plugin install git@claude-code-plugins
```

Or for local development:

```bash
/plugin install ./plugins/git
```

## Migration Notice

**git-commit skill and /commit command have moved to the `melodic-software` plugin.**

To create commits, use:

```text
/melodic-software:commit
```

Or invoke the skill:

```text
skill: melodic-software:git-commit
```

## Components

### Skills (8)

| Skill                  | Description                                                 |
| ---------------------- | ----------------------------------------------------------- |
| `git:push`             | Push operations with force-push safety (force-with-lease)   |
| `git:config`           | Configuration, aliases, performance tuning, credentials     |
| `git:gpg-signing`      | GPG commit signing setup and troubleshooting                |
| `git:hooks`            | Pre-commit hooks, Husky, lefthook, secret scanning          |
| `git:line-endings`     | Cross-platform line ending configuration                    |
| `git:setup`            | Git installation and initial configuration                  |
| `git:gui-tools`        | GitKraken, Sourcetree, GitHub Desktop                       |
| `git:gpg-multi-key`    | Advanced multi-key GPG for consultants/CI/enterprise        |

### Agent (1)

| Agent                  | Description                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| `history-reviewer` | Strictly read-only git history exploration (log, blame, show, diff, status, stash list)  |

The `history-reviewer` agent provides smart summaries of verbose git output to preserve main context tokens. It CANNOT commit, push, or modify the repository.

## Usage Examples

### Git History Summary

Use the agent for concise summaries:

```text
Use the history-reviewer agent to summarize the recent git log
```

```text
Use the history-reviewer agent to show who authored the changes in src/auth.ts
```

### Configure GPG Signing

```text
skill: git:gpg-signing
```

### Set Up Git Hooks

```text
skill: git:hooks
```

### Push with Safety

```text
skill: git:push
```

## Safety Features

The git plugin enforces several safety protocols:

- **No force push to main/master** without explicit confirmation
- **Force-with-lease** for safer force pushes
- **Hooks management** for pre-commit, secret scanning
- **Cross-platform** line ending configuration

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

- `melodic-software` - Git commit workflows with Conventional Commits
- `claude-ecosystem` - Meta-skills and documentation management
- `code-quality` - Code review and linting

## License

MIT
