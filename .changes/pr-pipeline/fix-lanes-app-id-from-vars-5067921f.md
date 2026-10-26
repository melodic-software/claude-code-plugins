---
bump: patch
---

### Fixed

- `ci-status` reads the lanes App's bot account id from the `AUTOMATION_LANES_APP_SENDER_ID` repository variable, its one source, at job level, instead of a literal id; the cost-hold step no longer sets its own copy. The trust-hold, cost-hold and lanes-hold steps keep failing closed, or keeping the hold, when the variable is not a numeric id. The lanes-hold step, which runs on every pull request and in the merge queue, fails red, and the cost-hold step keeps its hold, when the variable is not the trusted-actor id of `merge.agent-identity` in the base commit's `pr-pipeline.yaml`, now part of the base config checkout.
