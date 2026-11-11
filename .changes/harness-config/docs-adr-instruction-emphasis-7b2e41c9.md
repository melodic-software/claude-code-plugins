---
bump: patch
---

### Changed

- `audit-instructions` I28 no longer exempts emphasis guarding a high-consequence area: the marker is flagged and downgraded, the directive keeps its scope and reason, and a rule that must hold every time is pointed at a hook, deny rule or CI check. A stated hard precondition stays a fact, but emphasis set on it is downgraded. The scanner note no longer calls bold lead-ins house style; a bold list-item label or defined term is structure. The persist-findings carve-out list matches. Recorded in ADR 0098.
