---
bump: minor
---

### Changed

- `audit-instructions`: prose restating a rule a deterministic check already enforces (a hook, a CI check, a linter rule, a test) is flagged for deletion with the enforcing check named, under a new enforced deletion tier that needs no watch. I5 drops the prose once a must-always rule is converted to a check instead of keeping both, I1 and I8 route an enforced line or step to I5, and protected-class rules in the instruction exception register still hold, with the check reported beside the hold. Eval case 6 now expects the CI-enforced PR-title step to be flagged for deletion rather than kept.
