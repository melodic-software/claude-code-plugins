---
bump: patch
---

### Changed

- `babysit_verify_evidence.py` reads the trusted-actor list, admission rules and pipeline config at a commit from a checkout whose HEAD is that commit, before the contents API. `BABYSIT_CONFIG_CHECKOUT` now takes several checkouts separated by `os.pathsep`, and the first one whose HEAD is the commit answers.
