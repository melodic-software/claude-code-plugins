---
bump: patch
---

### Changed

- **Shared `exec-bash.mjs` launcher synced.** The launcher gains `--run-if-any-set`, `--run-if-settings-mention`, `--skip-unless-marker` and `--marker-root`, which the autonomy and disk-hygiene Stop rows use to skip starting bash on a turn where their script would exit at once. Its `readStdin` now resolves `{ input, stalled }`, and `check-bash-file-changes.mjs` reads that shape, so a stalled payload still records and checks nothing.
