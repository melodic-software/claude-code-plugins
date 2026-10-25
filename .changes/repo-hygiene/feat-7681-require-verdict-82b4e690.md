---
bump: minor
---

### Added

- The vendored `hooks/exec-bash.mjs` launcher takes `--require-verdict`, a per-row opt-in for a blocking hook row: it names a marker file in the script's `EXEC_BASH_VERDICT_FILE`, and a script that exits 0 without writing it is denied (exit 2, one stderr line), because Windows Git Bash reports a crashed bash as exit 0 with empty output. This plugin's rows do not pass the flag, so they behave as before.
