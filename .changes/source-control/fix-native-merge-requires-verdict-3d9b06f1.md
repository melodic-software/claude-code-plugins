---
bump: patch
---

### Added

- `babysit_verify_evidence.py evidence --repo R [--max-fails N] <pr> <head>` prints the gate's verifier evidence for one pull request as one JSON line, which the pr-merge lane's native auto-merge arms on.
