---
bump: patch
---

### Changed

- `/testing:run-e2e`'s render checks say no per-check catch rate is measured yet: `playwright-cli` cannot run inside `claude plugin eval`'s Bash on Linux, so browser eval cases move to an MCP-driven harness (#7137), and a quoted catch rate names the path it measured, CLI or MCP. The browser-tool rubric rows are unchanged.
