---
bump: minor
---

### Added

- `/guardrails:setup apply install-git-hooks scope=user` installs the `commit-msg-convention`
  entry once for the user as a git config hook (git 2.54 or later), loaded under an `includeIf`
  the operator chooses. It covers every clone and linked worktree the condition matches and runs
  beside lefthook, husky, the pre-commit framework or a `core.hooksPath` setup. The stable copy
  lives under `~/.config/git/checks/guardrails/`, the hook is named
  `guardrails-commit-msg-convention`, and `checks.skipmissing` stays the only skip
  ([#9775](https://github.com/melodic-software/claude-code-plugins/issues/9775)).
