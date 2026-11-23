---
bump: patch
---

### Fixed

- The pull-request skill's dependency review sets owner reason `security` only for a HIGH or CRITICAL risk the update itself carries, named with its severity in `reasons`; a red `ci-status` from a repository hold, such as the trust-gate hold, never sets it.
