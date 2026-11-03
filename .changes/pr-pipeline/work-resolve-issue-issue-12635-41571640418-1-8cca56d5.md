---
bump: minor
---

### Added

- `limits.stranded-backoff-hours` sets, per cause (`no-run`, `no-report`, `failed-again`, `failed-mint`, `kill-switch`), the base hours of work-unblock's re-fire backoff for a stranded `agent-ready` issue, doubled once per re-fire already made and held at 24 hours. Every cause defaults to 3 hours, the base before this key existed.
