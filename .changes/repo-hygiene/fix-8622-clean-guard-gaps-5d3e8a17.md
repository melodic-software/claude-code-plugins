---
bump: patch
---

### Fixed

- The clean skill's destructive guard parses the command lines a Bash command hands on, so these no longer slip past it during a clean run: a `$()` or backtick substitution inside double quotes or an unquoted here-doc body (`x="$(git stash drop)"`), an `eval` operand, a `bash -c` behind `sudo`, `timeout`, `env` or `xargs`, an `ssh` remote command, a script a shell or `ssh` reads from a here-string, a here-doc or a pipe (`printf … | bash`), and a git global option with a separate value (`git --git-dir <dir> reset --hard`) (#8622). Text that bash does not run, such as single-quoted text or a quoted here-doc body, still passes.
- The guard stays armed when `CLAUDE_PLUGIN_DATA` names another plugin's data directory, and blocks when its `hook-utils.sh` does not load, instead of allowing every command.
