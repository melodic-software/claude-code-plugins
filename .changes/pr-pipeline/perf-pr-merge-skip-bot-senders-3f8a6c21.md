---
bump: patch
---

### Changed

- pr-merge's `merge` and `enable-auto-merge` jobs now skip a bot-sent `pull_request_target` run in the job condition, before the job joins its concurrency group. Such a run used to wait in the `queue: max` line and then stop at `who.mjs`, since a bot is never a listed human. `who.mjs` is unchanged and stays the check; schedule, `workflow_dispatch` and push runs are not gated on the sender.
