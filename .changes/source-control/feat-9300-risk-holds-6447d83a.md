---
bump: minor
---

### Changed

- The unattended merge gate holds on a review flag only for a cost increase, a trusted-actor widening or a CRITICAL security finding. Open claude-review findings and lower security findings are listed in the reasons comment as `findings:<lane>` and no longer hold the merge.
- A change that adds or widens an entry in `.github/standards/trusted-actors/trusted-actors.json` always scores HIGH as `trust-gate:trusted-actors` and waits for the owner, whatever `merge.diff-check.high-path-floor` says; a change that only removes entries merges.
