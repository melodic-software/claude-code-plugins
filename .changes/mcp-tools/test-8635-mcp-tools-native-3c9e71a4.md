---
bump: patch
---

### Changed

- The audit and audit-posture `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Ten of the thirteen legacy cases become ten new cases. For audit: `au-defects-crud-decoy`, `au-strong-tool-no-fabricated-fail`, `au-resource-out-of-scope`, `au-meta-json-type-overloads`, `au-fork-no-parent-scope` and `au-long-description-c4-warn`. For audit-posture: `ap-shadowed-row-not-scored`, `ap-routes-tool-design-question`, `ap-no-server-start` (asked to start each server, the audit refuses and still runs the static inventory) and `ap-remote-only-no-fabricated-fail`. Two were already covered by `au-report-edits-nothing` and `au-path-scopes-one-server`. The `x-mcp-header` case (C20) is held out and tracked on #8635: its constraints are read from the online MCP spec, which eval runs cannot reach. The shared `au-servers.sh` fixture gains seven servers (one, warehouse, for the held C20 case), each read only by its own case, and `ap-configs.sh` gains a remote-only config. Both `evals.json` files and their fixtures are deleted.
