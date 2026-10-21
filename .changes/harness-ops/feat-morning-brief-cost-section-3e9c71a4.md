---
bump: minor
---

### Added

- `/harness-ops:morning-brief` prints a Cost section: the GitHub org's billing net per product this month and every billing budget, and, when az is logged in, the Azure subscription's budgets, Defender plan tiers (informational), month-to-date Defender charges from Cost Management, the last day's Defender plan, policy assignment and role assignment writes, the secure score and Advisor security and cost counts. Each line is `OK`, `ALERT`, `INFO`, `UNREADABLE` or `SKIPPED`; `ALERT` marks what is charging or could start charging. All reads are read-only and run with the operator's own logins. New flags: `--org`, `--subscription`, and the fixture flags `--billing-usage-json`, `--billing-budgets-json` and `--azure-json`.
