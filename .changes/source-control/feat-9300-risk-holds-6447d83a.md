---
bump: minor
---

### Changed

- The unattended merge gate holds on a review flag only for a cost increase, a trust-gate change or a CRITICAL security finding. Open claude-review findings and lower security findings are listed in the reasons comment as `findings:<lane>` and no longer hold the merge.
- Trust-gate paths (the trusted-actor list, the risk scorer and the config it reads, the merge gate, and the security review workflow) always score HIGH as `trust-gate:<glob>` and wait for the owner, whatever `merge.diff-check.high-path-floor` says.
