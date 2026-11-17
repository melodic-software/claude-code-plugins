---
bump: minor
---

### Added

- `profiles.mjs start [<profile>] [claude arguments]` starts `claude` in a profile: it writes the one-session file, drops the inherited profile variables, passes your other arguments through, and exits with claude's status. With no profile it asks which, by number, and refuses when nobody is there to answer ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- A resumed session keeps its profile: the session-start hook records the profile each session runs in, `start --resume <id>` and `start -c` resume in it, and a session resumed with plain `claude --resume` is told the command that resumes it in its profile ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).

### Changed

- `--for folder` now writes the `.claude/settings.local.json` Claude Code reads: in a git repository, the one at the main checkout's root, for every worktree and subdirectory; on Windows, outside git, or where the repository root is your home folder or not yours, the folder's own file. `status` says when the file is read by every worktree, and a folder switch names the live sessions in every worktree of the repository ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- The record of what apply wrote now lives in the repository's `.git/plugin-profiles/` for a folder in git and in `~/.claude/plugin-profiles-state/` for user settings, so it survives a lost plugin data folder; a record already in the data folder is still found, and the next apply moves it ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).

### Fixed

- A copy of the tool outside the plugin cache, such as a worktree or `--plugin-dir` copy, run from a shell that another plugin's `CLAUDE_PLUGIN_DATA` reached, no longer writes its records and session files into that plugin's data folder, where the installed copy's `status` and `clear` could not find them ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- A one-session file now names every skill a profile can hide, so a skill a folder profile hides no longer stays hidden in a one-session profile that keeps it ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `clear` names each entry edited since the apply that it is about to put back, with its value now, the profile's and the one it restores ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `status` names a profile an earlier version applied to a worktree's or subdirectory's own `.claude/settings.local.json` as partly in force, and `clear --for worktree` puts that file back ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `clear` with no record, in a file that still holds plugin or skill entries, says it cannot tell which a profile wrote and changes nothing, instead of saying there is nothing to clear ([#16893](https://github.com/melodic-software/claude-code-plugins/issues/16893)).
- `start` takes `always-on` by name and lists it in the picker; a SIGTERM or SIGHUP sent to `start` reaches `claude` and `start` waits for it to exit; on Windows `start` runs `claude.exe` without a shell, so an argument with a space or `&` arrives whole ([#16914](https://github.com/melodic-software/claude-code-plugins/pull/16914)).
