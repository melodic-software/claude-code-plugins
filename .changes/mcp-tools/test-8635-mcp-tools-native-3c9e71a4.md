---
bump: patch
---

### Changed

- The audit and audit-posture `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Eleven of the thirteen legacy cases become eleven new cases. For audit: `au-defects-crud-decoy`, `au-strong-tool-no-fabricated-fail`, `au-resource-out-of-scope`, `au-meta-json-type-overloads`, `au-fork-no-parent-scope`, `au-x-mcp-header-c20` and `au-long-description-c4-warn`. For audit-posture: `ap-shadowed-row-not-scored`, `ap-routes-tool-design-question`, `ap-no-server-start` (asked to start each server, the audit refuses and still runs the static inventory) and `ap-remote-only-no-fabricated-fail`. The other two were already covered by `au-report-edits-nothing` and `au-path-scopes-one-server`. The shared `au-servers.sh` fixture gains seven servers, each read only by its own case, and `ap-configs.sh` gains a remote-only config. Both `evals.json` files and their fixtures are deleted.
