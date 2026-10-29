---
bump: minor
---

### Added

- `block-cross-domain` now denies, from a session whose directory is in one identity domain, a Bash or PowerShell command that puts another domain's `identity_markers` entry in an identity position: the URL of `git remote add` or `set-url`, the value of `git config` or `git -c` for `user.email`, `user.name`, the `author.*` and `committer.*` keys or `remote.<name>.url`, `git commit --author`, and an assignment to `GH_CONFIG_DIR`, `AZURE_CONFIG_DIR` or a `GIT_AUTHOR_*` or `GIT_COMMITTER_*` variable. The same marker in a commit message or an `echo` is allowed, as is every call from a neutral directory. The deny is a stdout decision document, and the guard still exits 0 on every call ([#9746](https://github.com/melodic-software/claude-code-plugins/issues/9746)).
