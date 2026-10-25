---
bump: patch
---

### Fixed

- `ci-status` reads the lanes App's bot account id from the `AUTOMATION_LANES_APP_SENDER_ID` repository variable, its one source, at job level, instead of a literal id; the cost-hold step no longer sets its own copy. The trust-hold, cost-hold and lanes-hold steps keep failing closed, or keeping the hold, when the variable is not a numeric id.
