---
bump: patch
---

### Changed

- Signal 6 (report-only audit) reads `maintenance-file-upstream-drift-issues`, the weekly drift workflow, in place of the deleted `maintenance-check-upstream-drift`, and says why each audit fails: the test-selection audit on findings, the drift filer on a failed issue write, an unreachable upstream or a check script that broke its exit contract.
