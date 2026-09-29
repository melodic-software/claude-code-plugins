# ADR 0007: Keep the PR body rule always-loaded

Status: accepted

## Decision

`.claude/rules/pr-body-contract.md` stays always-loaded, with no `paths:` scope. Sessions that
open a pull request through the web or MCP never read a file the rule could be scoped to, so a
scoped rule would not load when it is needed.
