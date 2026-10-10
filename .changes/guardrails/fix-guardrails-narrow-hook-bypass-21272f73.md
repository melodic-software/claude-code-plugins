---
bump: patch
---

### Changed

- **`block-hook-bypass` leaves repository files to the shell file-change check.** A `cat >`, `echo`/`printf >` or same-command staged-move write whose target is a non-ignored path in the cwd's repository, tracked or not, no longer blocks: `check-bash-file-changes` runs the Write | Edit content guards on that file after the command. A git-ignored target (`.work/`), one under `.git`, one outside the cwd's repository or in a nested one, a move onto a directory, and any target the guard cannot place (quoted, variable-carried, relative after a `cd`) still block, as does every such write while `bash_file_change_check_enabled` is false or the plugin has no data directory. The python and PowerShell lanes are unchanged (#6689).
