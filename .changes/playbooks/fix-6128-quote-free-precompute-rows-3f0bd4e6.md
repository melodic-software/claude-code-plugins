---
bump: patch
---

### Fixed

- **`skill-authoring` precomputed-context guidance no longer teaches the brace-group fallback.**
  Claude Code's shell permission check refuses an injected command holding a brace group or a
  subshell, so a skill written to the old `{ probe || echo "..."; } | head -20` example never loaded
  outside auto mode. The reference now forbids grouping in injected commands, records the three
  refusal messages from a Claude Code 2.1.296 headless probe, and replaces the example with a
  repeated-guard list (`guard && probe | head -20 || guard || echo ...`) that renders the same with
  and without `pipefail`. The `pipefail` section records that the probe ran without it.
