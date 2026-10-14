---
bump: minor
---

### Added

- The security binding takes an optional `admission.rule_admission[]` of owner-written C1/C2 rules, each `{id, work_class, proposed_class}`; the schema and `check-security-binding.mjs` validate it, and the admission-policy leaf's "Rule admission" section defines the precedence, shared predicate and trust-surface deny list.
