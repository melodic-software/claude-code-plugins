---
bump: patch
---

### Changed

- **Shared `exec-bash.mjs` launcher synced; no change to this plugin's hooks.** The launcher gains `--run-if-any-set`, `--run-if-settings-mention`, `--skip-unless-marker` and `--marker-root`, which the autonomy and disk-hygiene Stop rows use to skip starting bash on a turn where their script would exit at once.
