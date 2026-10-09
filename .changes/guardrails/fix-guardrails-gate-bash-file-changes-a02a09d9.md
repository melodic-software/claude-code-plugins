---
bump: minor
---

### Added

- **`check-bash-file-changes` gates what a shell command wrote, not how it was spelled.** A PreToolUse fire on Bash and PowerShell records `git status` and each dirty path's size and mtime for the repository holding the call's cwd; the PostToolUse and PostToolUseFailure fires run the guards of the PreToolUse Write | Edit row (secret-pattern-detection, hardcoded-path-check, block-windows-drive-tmp) on each file the command changed, as the Write of a new file or the Edit of the lines a tracked file adds. `node x.js` or `python3 x.py` writing a repository file now meets the same checks as an Edit of it, and a finding reaches Claude with the guard's own message. It fails open outside a git repository, and `bash_file_change_check_enabled` switches it off. `block-hook-bypass` is unchanged (#6674).
