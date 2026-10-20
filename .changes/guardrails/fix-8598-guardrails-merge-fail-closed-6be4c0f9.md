---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` fails closed when it cannot resolve the merge target (#8598).** A `gh pr merge` or REST merge whose repository or PR number came from a shell variable (`-R $R`, `$n` in a loop), `$(...)` or backticks used to run unchecked with a notice, so any variable skipped the thread, change-request and check gate. Those merges, and a bare `gh pr merge` whose current branch cannot be read or has no open PR, are now blocked with the fix: write `gh pr merge <number> -R owner/repo` literally. A merge command holding a backtick outside single quotes is blocked too, since the target the guard read need not be the one the shell runs, and so is a command holding more than one merge, of which only the first used to be checked: run each merge as its own command. A literal target is checked as before, whatever other flags (`--body`, `--match-head-commit`) take from a variable.
