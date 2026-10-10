---
bump: patch
---

### Fixed

- **`check-bash-file-changes` said nothing when it left a change unexamined.** It now reports each skip as `additionalContext` ("N changed files not examined: <reason>"), and adds it to the block reason when a finding blocks: files past the first 20 in path order or past the time budget, commits past the last 20 one command made, a `git status` that failed or listed more than 10000 paths (at the snapshot or the check), a new symbolic link, which is never followed, no snapshot recorded before the command, no bash to run the guards, and a `run_in_background` command, whose later writes are not checked. A run that skips nothing stays quiet ([#6709](https://github.com/melodic-software/claude-code-plugins/issues/6709)).
