---
bump: patch
---

### Changed

- **audit:** the fix flow's concurrent-edit guard runs through `scripts/digest-guard.sh`, which creates the run directory (`init`), records a file's sha256 in one flat state file under `<run>/digests/` (`record`), and compares it before each write (`check`, exit 1 on a mismatch). It refuses a run directory outside its state root, symlinks resolved, so a lane can allow the script by path in place of open `sha256sum` and `mkdir` rules. The skill no longer grants `sha256sum` or `shasum`. ([#10529](https://github.com/melodic-software/claude-code-plugins/issues/10529))
