---
bump: minor
---

### Added

- `block-cross-domain` denies a command that writes the machine's git identity, from every session: in a domain, from a neutral directory, and on a host with no domain map ([#9748](https://github.com/melodic-software/claude-code-plugins/issues/9748)). That covers a `git config` with `--global`, `--system` or `--file <identity file>` that sets, adds, replaces or unsets `user.email`, `user.signingkey`, `user.useConfigOnly`, `credential.helper`, `core.sshCommand`, `core.hooksPath` or an `includeIf` key, and a shell write (a redirection, `tee`, `cp`, `mv`, `sed -i` and the like, or a PowerShell writer) to `~/.gitconfig*`, a `*.gitconfig` file or a path the map's `identity_files` lists. Reads pass: `--get`, `--list`, `git config get` and `list`, and a command that only reads the file. With no map the guard now reads each command and parses one whose text holds both `git` and `config`, still starting no process. The compiled map cache moves to format 4, so each map is compiled once more after the update.
