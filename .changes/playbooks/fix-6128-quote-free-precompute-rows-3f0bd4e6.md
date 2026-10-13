---
bump: patch
---

### Fixed

- **`skill-authoring` precomputed-context guidance no longer teaches the brace-group fallback.**
  In a Claude Code 2.1.296 headless probe, the shell permission check refused an injected command
  holding a brace group or a subshell, so a skill written to the old
  `{ probe || echo "..."; } | head -20` example did not load in default permission mode. The
  reference now forbids grouping in injected commands, points at the probe command and rows in
  #7068, and replaces the example with a repeated-guard list
  (`guard && probe | head -20 || guard || echo ...`) that renders the same with and without
  `pipefail`.
