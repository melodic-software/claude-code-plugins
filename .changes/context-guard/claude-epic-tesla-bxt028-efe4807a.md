---
bump: minor
---

### Added

- **An optional prompt-cache status-line segment.** `scripts/cache-line.mjs` reads the status line's `prompt_cache` object and prints one line: warm with the expiry clock time and lifetime, or cold with the tokens the next message re-caches, plus the hit ratio and, after a miss, its count and cause. It shows a clock time rather than a countdown because Claude Code re-runs the status line when a warm cache expires, so it needs no `refreshInterval`. It prints nothing before the first response or on a payload without the object. `/context-guard:setup apply cache-line` copies it to `~/.claude/context-guard/cache-line.mjs`, a path that survives plugin updates, and prints the `statusLine` edit to paste; `check` reports a stale copy. The module is unchanged: a mod's `$.session.usage()` carries no cache expiry, so the band row would have to guess it.

### Removed

- **`scripts/prompt-cache-cause.py`.** Nothing called it. The cache segment prints the same `last_miss_cause.causes` names, and the reader contract's "Prompt cache" section now points at it.
