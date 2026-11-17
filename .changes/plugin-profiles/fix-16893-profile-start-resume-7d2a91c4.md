---
bump: patch
---

### Fixed

- A copy of the tool outside the plugin cache, such as a worktree or `--plugin-dir` copy, run from a shell that another plugin's `CLAUDE_PLUGIN_DATA` reached, no longer writes its records and session files into that plugin's data folder, where the installed copy's `status` and `clear` could not find them ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
