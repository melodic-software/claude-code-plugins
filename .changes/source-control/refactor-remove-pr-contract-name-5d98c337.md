---
bump: patch
---

### Removed

- `pr-body-linkage-gate` and `pr-linkage-mcp-gate` no longer gate on a workflow that uses the contract composite's old path; they gate only where a workflow uses `.github/actions/pr-require-checks/check-contract`, which every consumer now pins.

### Changed

- The linkage gates' block message and status text name the `check-contract` step, as do the plugin README, the `/source-control:pull-request` create reference and the `/source-control:setup` convention interview.
