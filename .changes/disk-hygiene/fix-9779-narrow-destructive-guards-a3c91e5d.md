---
bump: patch
---

### Fixed

- The plugin-level engine gate no longer denies a Bash command that only reads the engine script ([#9779](https://github.com/melodic-software/claude-code-plugins/issues/9779)). A list or pipeline whose every command is a reader (`cat`, `head`, `tail`, `wc`, `grep`, `rg` without `--pre`, `git show`/`log`/`diff`/`grep`, `gh issue`/`pr`, or `sed` printing line ranges such as `sed -n '1,40p'`) defers, even when it names the engine by its own path, and the body of a here-document with a quoted delimiter (`<<'EOF'`) is read as data. A command outside that set, an unquoted here-document delimiter, a here-string, a backslash or a lone `&` keeps the command gated as before. The PowerShell lane is unchanged.
