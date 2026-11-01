---
bump: patch
---

### Added

- Ten `claude plugin eval` outcome cases: five for `/mcp-tools:audit-posture` (`ap-`: floating versions, a mutable image tag, withheld env and header values, an instruction-shaped server name, unverified provenance) and five for `/mcp-tools:audit` (`au-`: a string `requiresUserInteraction`, undescribed parameters, over-long server instructions, path scoping, edits nothing). Every grader is deterministic and carries offline samples. Shared fixtures are written by seed scripts under `evals/fixtures/`.
- The frozen `/mcp-tools:audit-posture` invocation probe set, `probes/audit-posture.json`, with 18 queries.
