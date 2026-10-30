---
bump: patch
---

### Changed

- `/review:security-review` holds `critical-security` only for a leak (a token, secret or signing
  key exposed, or a token's scope grown), a compromise of the owner's accounts or machines, or a
  charge. A new "Owner threat model: throughput phase" section makes weakening, narrowing or
  removing a path, trust-path, person-approval or bot-author hold, or a pin ceremony, no
  finding. A hold on untrusted provenance or an untrusted spec is still judged. The section reads
  the owner decision from the tracked loop-lane record, never from the pull request. A kill switch
  that can no longer stop a lane stays a finding but is never CRITICAL on its own. Deleting the
  section brings back findings for those hold removals; the narrowed severity bar and the kill
  switch cap stay. Three eval cases cover a path-hold removal (no hold), a token scope widening
  (held) and a billable runner (cost hold).
