---
bump: patch
---

### Changed

- A changed trust-gate path no longer holds a pull request by itself: the review callers' `hold-paths` only sends those files to extra security scrutiny, and the security lane judges them. An exempt author's pull request (Dependabot, the release App, the standards-sync App), which no review lane reads, still fails on a trust-gate path.
- The verifier fails a change to the takeover set only when it lets someone outside the organization gain trust or weakens a check beyond the spec, treats only a hold on a real charge (not model, effort, turn, timeout or schedule spend) as a hold the owner keeps, and passes a diff too large to judge whole with notes naming the parts it could not judge.
- ci-status's cost-only clear is no longer blocked by every lanes App comment in the window, only by a lanes App escalation comment.
- The lost-run reconciler re-runs a pr-verify run whose first attempt failed or was lost after its judge step started, once. pr-verify fails a run the lanes kill switch stopped, so the reconciler re-runs it once the switch is off instead of leaving the head with no verdict.
