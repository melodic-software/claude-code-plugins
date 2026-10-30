---
bump: patch
---

### Changed

- `/review:security-review` holds `critical-security` only for a leak (a token, secret or signing
  key exposed, or a token's scope grown), a compromise of the owner's accounts or machines, or a
  charge. A new "Owner threat model: throughput phase" section makes weakening, narrowing or
  removing a merge, path, trust-path, person-approval or bot-author hold, or a pin ceremony, no
  finding, and reads the owner decision from the tracked loop-lane record instead of the pull
  request. A kill switch that can no longer stop a lane stays a finding but is never CRITICAL on
  its own. Deleting that one section restores the hardened criteria. Three eval cases cover a
  path-hold removal (no hold), a token scope widening (held) and a billable runner (cost hold).
