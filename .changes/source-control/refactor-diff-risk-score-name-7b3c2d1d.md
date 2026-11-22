---
bump: patch
---

### Changed

- The babysit-prs diff risk scorer is now `scripts/diff_risk.py` (was `babysit_risk.py`), with its tests in `tests/test_diff_risk.py` and `tests/test_diff_risk_cost.py`, so the deterministic diff risk score is named apart from `/review:merge-risk`'s merge-risk rating. The hold floor lists the new path.
