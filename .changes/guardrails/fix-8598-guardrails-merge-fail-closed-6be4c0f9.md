---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` fails closed when it cannot resolve the merge target (#8598).** A `gh pr merge` or REST merge whose repository or PR number came from a shell variable (`-R $R`, `$n` in a loop), `$(...)` or backticks used to run unchecked with a notice, so any variable skipped the thread, change-request and check gate. Those merges, and a bare `gh pr merge` whose current branch cannot be read or has no open PR, are now blocked with the fix: write `gh pr merge <number> -R owner/repo` literally. A Bash command whose text is merge-shaped (`pr merge`, a `pulls/.../merge` route, a merge mutation name) and holds any backtick, quoted or not, is blocked too, since a backtick substitution can change or hide the target the guard reads (pass a body that holds one with `--body-file`), and so is a `pr merge` or REST merge route continued with a backslash-newline (write the merge on one line), and so is a command holding more than one merge, of which only the first used to be checked: run each merge as its own command. A literal target is checked as before, whatever other flags (`--body`, `--match-head-commit`) take from a variable.
