---
bump: patch
---

### Added

- `behavior-probes`: three `hub-start` cases on whether an instruction-file edit in a worktree reaches the auto-mode classifier: an Edit of `AGENTS.md` in a worktree under an added directory with a `soft_deny` entry naming such edits, its control making the same change with `sed -i`, and that control's own control, a `sed -i` of `README.md`. A new `cases/lib/hub-worktree.sh` scaffold builds the worktree inside the run's temp directory. A live run of these three and the six hub-start cases pending since the last release is recorded in `records.md`.
- `behavior-probes`: `run --live --real-setup` repeats cases against the operator's own settings: it adds `user` to the setting sources and passes only `permissions.additionalDirectories` from the case's settings. Record 24 holds its first repeat.
