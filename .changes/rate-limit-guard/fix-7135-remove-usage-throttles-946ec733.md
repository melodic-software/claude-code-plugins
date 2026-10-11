---
bump: major
---

### Changed

- **Breaking:** `model_notices` replaces `rate_limit_lines_enabled` and is off by default. Off, nothing from this plugin enters Claude's context; the toast, transcript line, band row, status tool and snapshot work as before. Set `model_notices` to `true` for the approach, threshold, reset and options lines; a stored `rate_limit_lines_enabled: true` no longer applies (#7135).

### Removed

- The reader contract's orchestration fallback, which told sessions to start agent fan-out narrow when rate-limit headroom could not be observed. Unobservable headroom is now reactive-only with no sizing rule (#7135).
