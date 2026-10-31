---
bump: patch
---

### Fixed

- `/session-flow:audit-sessions` no longer counts every `Monitor` call in `polling_calls`. A Monitor command now counts the way a Bash command does: as polling only when it is itself a poll loop (a `sleep`, a `while` or `until` loop, or `watch`), and as a CI wait when it runs `gh run watch` or `gh pr checks --watch`. A Monitor tailing a file is the event-driven wait the harness recommends and no longer inflates the polling metric.
