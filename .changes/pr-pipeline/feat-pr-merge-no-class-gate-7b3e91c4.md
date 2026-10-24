---
bump: minor
---

### Changed

- `merge.rung` is a pacing cap: no work class is read, and no class, missing class or diff shape caps it. The only check that names a class is the local babysit lane's untrusted-provenance hold. That lane also needs a human to vouch for the linked issue: a write-access human wrote it, or one applied the admission label in person with no body edit after. The risk score's `class-contradicted`, `blast-radius-missing` and rung reasons are gone (#9668).
- `merge.diff-check.c2-contradictions` is deprecated and has no effect. The schema still accepts it so existing configs validate.
