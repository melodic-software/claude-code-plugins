---
bump: patch
---

### Changed

- The hourly work-unblock sweep reads closes from 15 minutes before the last successful scheduled sweep (at most 3 hours back; the full 3 hours when that run cannot be read) instead of always the last 3 hours. Metric: sweep passes per closed issue. Baseline: about 3 (hub measurement). Expected: about 1.
