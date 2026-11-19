---
bump: patch
---

### Fixed

- The PR-body linkage hooks (`pr-body-linkage-gate`, `pr-linkage-mcp-gate`) enforce again in a repository whose ci-status job runs the ci-workflows `report-ci-status` composite, which runs check-contract inside it. Before, they stopped checking in every repository moved to that composite.
