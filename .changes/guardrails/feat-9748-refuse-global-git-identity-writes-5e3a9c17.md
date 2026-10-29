---
bump: minor
---

### Added

- `block-cross-domain` now denies a global git identity write in every domain, neutral included ([#9748](https://github.com/melodic-software/claude-code-plugins/issues/9748)). It refuses a `git config` write with `--global`, `--system` or `--file <identity file>` to `user.email`, `user.signingkey`, `user.useConfigOnly`, `credential.helper`, `core.sshCommand`, `core.hooksPath` or an `includeIf` key. It also refuses a shell write to `~/.gitconfig*`, any `*.gitconfig`, or an entry of the domain map's `identity_files` globs. Reads (`--get`, `--list`, `git config get`) pass. The deny is a `permissionDecision` on stdout, and every exit is still 0. With no map, the guard still checks nothing.
