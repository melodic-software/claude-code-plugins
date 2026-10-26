---
bump: patch
---

### Fixed

- The `pr-body-linkage-gate` and `pr-linkage-mcp-gate` hooks enforce again in a repository that wires in the contract composite at its current path, `.github/actions/pr-require-checks/check-contract`. Their scope guard matched only the old `.github/actions/pr-contract` path, so after the composite's rename neither hook fired anywhere that had moved to the new one. Both paths now count.
