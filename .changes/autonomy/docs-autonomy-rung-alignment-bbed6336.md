---
bump: patch
---

### Changed

- The isolation ladder names the CI-lane surface on GitHub-hosted runners: under the five conditions of ADR 0049 it runs unattended without default-deny egress, and every other surface keeps the `L2` floor.
- The work-class contract states that no merge rung reaches `C4` or `C5`, and that the pr-merge lane reads no class and merges on the verifier verdict.
