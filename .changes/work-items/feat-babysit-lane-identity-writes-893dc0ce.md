---
bump: minor
---

### Added

- work-loop: where the target repository names a `merge.agent-identity`, a lane-start identity preflight confirms the session acts as that identity and holds no other account, and ends the run before any triage, claim, label or PR write when it does not.
- triage: "Lane barred from recording a class" records whose credential label writes carry: an unattended lane's run under the identity, while interactive label writes stay under the operator and count as human provenance (a named residual).

### Changed

- work: the pre-push auto-merge disarm no longer says the merge lane re-arms; no lane arms auto-merge.
