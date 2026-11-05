---
bump: patch
---

### Removed

- `babysit_verify_evidence.py refusal-stands` is gone, with `babysit_postmerge.py`'s `content_refusal` and `refusal_moved` and the `running` option of the idle tick's verifying-runs read: pr-merge's PR-scoped wake no longer asks whether the last sweep's refusing report still stands, since over its first 24 hours the probe never let a wake skip its fresh check. The idle tick's `judgedRuns` reading is unchanged.
