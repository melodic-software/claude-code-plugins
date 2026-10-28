---
bump: patch
---

### Changed

- `babysit_risk.FLOOR_CLASSES` is the one hold-floor table: `scripts/sync-hold-floor.py` writes its copies (merge-holds.mjs `HOLD_PATH_CLASSES` and `COST_PATHS`, the review callers' `hold-paths`, ci-status's `hold_patterns`), and `test_merge_holds_sync.py` runs `sync-hold-floor.py --check` in place of comparing the copies. The floor holds that generator as `gate`, so a change to it waits for a person.
