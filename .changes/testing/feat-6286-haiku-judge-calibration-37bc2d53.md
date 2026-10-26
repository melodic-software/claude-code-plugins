---
bump: patch
---

### Changed

- The judge calibration sweep (`metrics.sh --sweep`) now runs Haiku at `low`, `medium` and `high` beside the Sonnet and Opus arms, and `calibration.md` records the Claude Haiku 5.5 result: `low` and `high` are significantly less accurate, and `medium` changed its verdict on 26 of 78 rows across three runs against 7 of 78 for the shipped `sonnet` `medium` default. Haiku stays out of the judge: `judge-lib.sh` no longer walks to it or accepts it as the fallback, and tests pin that. This round's sweep files sit in `sweep-haiku-5-5/`, apart from the older-prompt arms (#6286).
