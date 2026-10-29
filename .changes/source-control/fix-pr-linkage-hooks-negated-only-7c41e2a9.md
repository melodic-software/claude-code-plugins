---
bump: patch
---

### Changed

- The `pr-body-linkage-gate` and `pr-linkage-mcp-gate` hooks block a PR body only when it carries a negated closing reference (`does not close #N`), which GitHub still closes on merge. A body missing a closing line or a `## Summary`, `## Fix`, `## Verification` or `## Related` section now passes, matching CI, which reports those as advisory. An MCP `create_pull_request` with no body passes too. The `/source-control:pull-request create` pre-create section check is unchanged.
