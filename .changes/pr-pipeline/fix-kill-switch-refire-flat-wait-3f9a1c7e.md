---
bump: patch
---

### Fixed

- work-unblock re-fires an issue the lanes kill switch stopped on a flat `limits.stranded-backoff-hours` `kill-switch` wait (1 hour here) after the refused run ended, past `limits.limit-stops-per-issue` trips, instead of doubling it per trip up to 24 hours. Trips below that bound keep their waits, kill-switch trips still never count toward a give-up, and the other causes still double. Breaker re-fires sort by when the refused run ended, so after the switch clears each sweep re-fires the oldest stranded issues first, up to `limits.restarts-per-run`.
