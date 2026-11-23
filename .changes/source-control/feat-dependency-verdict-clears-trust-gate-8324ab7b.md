---
bump: patch
---

### Changed

- `pull-request` `dependency --ci` tells the model that when `merge_clears_gate_hold` is true its `merge` alone clears the trust-gate hold on an action of an owner the repository does not trust by name, so it applies the review-only checks and reads the code between the old and new action commit before `merge`.
