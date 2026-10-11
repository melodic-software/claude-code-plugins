---
bump: patch
---

### Fixed

- `pull-request` and `babysit-prs`: the cloud-session polling rule no longer says cloud sessions have no PR-event route. It keeps the decision to poll, with a pointer to the upstream auto-fix section, an as-of date and a recheck trigger.
- The `pr-linkage-mcp-gate` docs and hook comment no longer say cloud sessions lack `gh`: `gh pr create` there is absent or refused by the cloud GitHub proxy, which is why PRs go through the MCP tools.
