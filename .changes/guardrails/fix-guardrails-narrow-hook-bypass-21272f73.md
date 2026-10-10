---
bump: patch
---

### Changed

- **`block-hook-bypass` leaves a single plain shell write to the shell file-change check.** A command that is one `cat >` or `echo`/`printf >` write and nothing else, to a non-ignored path in the cwd's repository, no longer blocks: `check-bash-file-changes` runs the Write | Edit content guards on that file after the command, and the guard takes that check's pre-command snapshot itself when the parallel snapshot hook has not yet. Because that check runs after the whole command and only reports, everything else still blocks: a second command (`&&`, `||`, `;`, `|`, a newline, a subshell or substitution), any redirect but one plain `>`/`>>` plus `2>&1`, `2>/dev/null` or a here-doc (so `&>`, `1<>` and fd-numbered writes), a `git`, `ln`, `mkdir`, `mv` or `cp` word, `run_in_background`, a staged move, a `.gitignore` target, a `.git` target including its `.git.` and trailing-space aliases, a git-ignored, outside or nested target, any target the guard cannot place, a call whose snapshot cannot be recorded, and every such write while `bash_file_change_check_enabled` is false or the plugin has no data directory. The python and PowerShell lanes are unchanged (#6689).
