---
bump: patch
---

### Added

- The pr-merge lane's verdict gate reader (`babysit_verify_evidence.py` `evidence`) now reports `supersededAtHead`: true when a counted FAIL at the head gave way under `_superseded` (a pass recorded after it and a trusted body edit or relink), false otherwise, including when the FAIL cap decided first or a read failed. pr-unblock's pass-only round reads it to resolve that FAIL's fail-note threads. The gate's decisions do not change.
