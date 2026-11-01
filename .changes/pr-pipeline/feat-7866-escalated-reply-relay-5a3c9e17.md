---
bump: minor
---

### Added

- A listed human's reply on a thread the pr-unblock lane escalated now starts address-feedback within one dispatcher pass. The new unprivileged `pr-review-comment-relay.yml` (`pull_request_review_comment` `created`, `permissions: {}`, no checkout, no secret) runs for a person's comment on a lane branch of this repository, and `pr-feedback-dispatch.yml` lists it under `workflow_run.workflows`. `feedback-dispatch.mjs` reads the relay run back, requires a listed human as its actor and re-runner (never the lanes App), the PR among its `pull_requests` and a thread the lane escalated that a listed human answered (a fix request alone keeps the tick's sweep), counts only check runs started after the relay run, and names the relay run as the record's upstream. check-trusted-trigger's new `run-dispatcher-relay` input accepts that upstream by path, event and actor id in both run files; the azure-iac broker matches it (ADR 0087). A reply on a conflicted PR, where GitHub starts no review-comment run, is picked up by the review run after resolve-conflicts pushes.
