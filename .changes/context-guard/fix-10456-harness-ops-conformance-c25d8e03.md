---
bump: patch
---

### Fixed

- Capture reference: hook stdin's main-session `context_tokens` on a resume, a fork or a model
  switch is recorded, and why it is no running occupancy reading. Reader contract:
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW` wins only when Claude Code accepts its value, and the default
  auto-compact thresholds are cited as the section they are.
