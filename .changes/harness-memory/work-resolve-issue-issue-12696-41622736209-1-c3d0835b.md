---
bump: patch
---

### Changed

- The `audit` and `stateless` skills no longer restate upstream facts: the `claude-md-management` plugin's skill and command, the auto-memory store path and relocation, what `/memory` edits, the scopes that set `autoMemoryDirectory`, and the meaning of each `CLAUDE_CODE_DISABLE_AUTO_MEMORY` value ([#12696](https://github.com/melodic-software/claude-code-plugins/issues/12696)). Each decision stays, and each now points at the upstream section with an as-of date and a recheck trigger.
