---
bump: patch
---

### Changed

- Among several pr-verify passes at the head, the merge gate's verifier reader (`babysit_verify_evidence.py`) now decides on those of the run that started last, as `resolve-pr.mjs` weighs them, so a pass judged again after a spec change replaces the stale one. Spec trust is unchanged; trusting lanes App spec text is held for an owner decision.
