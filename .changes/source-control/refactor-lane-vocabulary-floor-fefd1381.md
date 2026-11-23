---
bump: patch
---

### Changed

- babysit-prs: the hold-floor pins in `test_floor_paths.py` and `test_merge_holds_sync.py` count `.github/scripts/lib/lane-vocabulary.mjs`, a trust-class floor row, which the merge-arm script now loads. No behavior changes.
