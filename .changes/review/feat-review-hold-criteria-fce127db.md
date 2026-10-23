---
bump: minor
---

### Added

- `/review:code-review` and `/review:security-review` return the review's optional `hold` field, when the wrapper's output schema has one, only for the hold classes: `cost` (a change that adds or raises model or API spend, code lane), `trust-gate` (a change to the trusted-actors list, the trusted-trigger action, a `CODEOWNERS` or a `.gitmodules` file) and `critical-security` (a CRITICAL security finding; the code lane only where no security lane runs). A hold adds nothing to the findings count, and every other flag stays a normal finding. A change in a hold class is no longer eligible for the code lane's trivial-change skip, nor a `trust-gate` change for the security lane's no-security-surface skip.
