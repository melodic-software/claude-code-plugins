---
bump: patch
---

### Fixed

- fix-ci now sees a failed check that a later skipped or neutral run of the same check hides, such as a contract-only run on a head whose `ci-status` stays red on the earlier failure; a later success still clears it.
