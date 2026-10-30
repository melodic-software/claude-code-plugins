---
bump: patch
---

### Fixed

- `/session-flow:audit-sessions` flags `hooks.stop_ms` and `time.active_s` again: their thresholds are the p90 of a fresh derivation on their current definitions, 152 ms and 19372 s, and `time.active_s` routes to `/session-flow:retro` as it did before. The derivation (672 interactive sessions, Claude Code 2.1.283-2.1.312, 2026-10-30) ships as `reference/threshold-derivation.md` with n, median and p90 per metric, and the basis of every other rule now gives its figures beside the earlier spike's. Those other thresholds are unchanged ([#10271](https://github.com/melodic-software/claude-code-plugins/issues/10271)).
