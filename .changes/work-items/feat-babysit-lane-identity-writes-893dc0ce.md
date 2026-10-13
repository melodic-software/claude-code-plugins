---
bump: minor
---

### Added

- work-loop: where the target repository names a `merge.agent-identity`, an identity gate at the start of every cycle reads `pr-pipeline.yaml` from the target's default branch, confirms the session acts as that identity and holds no other account, runs `lane-push.sh --check`, and ends the run before any triage, claim, label, PR or push write when it does not or the config is unreadable.
- triage: "Lane barred from recording a class" records whose credential label writes carry: an unattended lane's run under the identity, while interactive label writes stay under the operator and count as human provenance (a named residual).

- `scripts/lane-push.sh`, the only way a lane pushes (generated from the shared `lib/lane-push.sh`): it builds the https URL itself, scrubs git's environment and global config, forces gh as the credential helper, refuses a default branch other than a fork's own, and pushes only as the named login.

### Changed

- work: every push a dispatched worker makes goes through `lane-push.sh --branch <name>` with the target's `merge.agent-identity` (else the session's login); the dispatch brief forbids a bare `git push`.

- work: the pre-push auto-merge disarm no longer says the merge lane re-arms; no lane arms auto-merge.
- work: the permission preflight no longer probes `git push`, which the lane never runs; it pushes only with `bash <plugin-root>/scripts/lane-push.sh …`, an interpreter-led call that the permission mode decides.
