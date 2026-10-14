---
bump: minor
---

### Added

- The security binding takes an optional `admission.rule_admission[]` of owner-written C1/C2 rules, each `{id, work_class, proposed_class}`; the schema and `check-security-binding.mjs` validate it, including a finding when `dispatch_posture` is `human-gated-only` or the decision table gates a rule's class. The admission-policy leaf's "Rule admission" section defines the precedence, shared predicate and trust-surface deny list, states that C1 rule admission is not yet enabled, and records agent-filed issues reading as owner-authored as an accepted risk.
