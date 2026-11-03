---
bump: patch
---

### Fixed

- The half-hourly address-feedback sweep (`pr-feedback-dispatch.yml`, `sweepUnsent`) now sends a lanes App pull request whose head has an unresolved review thread and no address-feedback round, 10 minutes after the last review or pr-merge run at that head finished, and no round for it was created since that review started. Before, a review completion that skipped on a cause that clears later, such as a pr-verify FAIL-cap read that did not fit in its time limit, left the head with no other trigger, and one advisory thread held the pull request until a person dispatched the round.
