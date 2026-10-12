---
bump: minor
---

### Added

- work-loop: where the target repository names a `merge.agent-identity`, an identity gate at the start of every cycle reads `pr-pipeline.yaml` from the target's default branch, confirms the session acts as that identity and holds no other account, and ends the run before any triage, claim, label or PR write when it does not or the config is unreadable.
- triage: "Lane barred from recording a class" records whose credential label writes carry: an unattended lane's run under the identity, while interactive label writes stay under the operator and count as human provenance (a named residual).

### Changed

- work: the pre-push auto-merge disarm no longer says the merge lane re-arms; no lane arms auto-merge.
