---
bump: patch
---

### Changed

- The hourly work-unblock sweep reads closes from 15 minutes before the last scheduled run whose labeling step succeeded (at most 3 hours back; the full 3 hours when that run cannot be read or did not sweep, as under the kill switch or a lane the config turns off) instead of always the last 3 hours. Metric: sweep passes per closed issue. Baseline: about 3 (hub measurement). Expected: about 1.
