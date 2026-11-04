---
bump: patch
---

### Fixed

- `limits.upstream-apply-changelog-per-day` no longer counts a run whose key credit-stopped. The
  model job now writes the start record after the leg, scanned, and skips it when the leg ended
  in a credit stop and its credit-stop marker uploaded; a setup failure before the leg and a
  credit stop with no marker still count. The job summary of a credit-stopped run, and of a run the credit window skips, says
  so (#13233).
