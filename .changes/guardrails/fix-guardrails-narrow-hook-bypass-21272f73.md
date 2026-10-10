---
bump: patch
---

### Changed

- **`block-hook-bypass` leaves a single plain shell write to the shell file-change check.** A command that is one `cat >` or `echo`/`printf >` write and nothing else, to a non-ignored path in the cwd's repository, no longer blocks: `check-bash-file-changes` runs the Write | Edit content guards on that file after the command, and the guard takes that check's pre-command snapshot itself when the parallel snapshot hook has not yet. Because that check runs after the whole command and only reports, everything else still blocks: a second command (`&&`, `||`, `;`, `|`, a newline, a subshell or substitution), any redirect but one plain `>`/`>>` plus `2>&1`, `2>/dev/null` or a here-doc (so `&>`, `1<>` and fd-numbered writes), a `git`, `ln`, `mkdir`, `mv` or `cp` word, `run_in_background`, a staged move, a `.gitignore` target, a `.git` target including its `.git.` and trailing-space aliases, a git-ignored, outside or nested target, a target holding any character outside `[A-Za-z0-9._/@+-]` (braces, `,`, `:`, `\`, `~`, `$`), an unquoted here-doc whose body has a line ending in `\`, any target the guard cannot place, a call whose snapshot cannot be recorded, and every such write while `bash_file_change_check_enabled` is false or the plugin has no data directory. The python and PowerShell lanes are unchanged (#6689).

### Fixed

- **`block-hook-bypass` sees stdout writes that never use a plain `>`.** `echo x &> f`, `&>> f`, `>& f`, `1<> f`, `3> f 1>&3` and `2> f 1>&2` wrote the file and passed; they now block like `echo x > f`, and `echo x 3>f > /dev/null 1>&3` no longer passes as a discard. `&> /dev/null` and `>&2` still pass.
