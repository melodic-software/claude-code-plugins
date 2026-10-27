---
bump: minor
---

### Added

- `hooks/exec-bash.mjs` takes `--require-verdict`, a per-row opt-in for a blocking hook row: the launcher names a marker file in the script's `EXEC_BASH_VERDICT_FILE`, and a script that exits 0 without writing it is denied (exit 2, one stderr line). A row without the flag behaves as before.

### Fixed

- A guard row no longer lets a call through when its dispatcher dies before reaching a verdict. Windows Git Bash reports a crashed bash (a stack overflow, 0xC0000005) as exit 0 with empty output, which read as an allow. Every guardrails row now passes `--require-verdict`, and `run-guards.sh` writes the marker as its last action at each deliberate exit, so a crash denies the call. An abort in the dispatcher's own code, which used to allow the call with a notice, writes no marker either and is now denied. A `--report` process, whose parent gives the answer, never writes it.
