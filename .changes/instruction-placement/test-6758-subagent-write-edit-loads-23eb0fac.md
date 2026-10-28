---
bump: patch
---

### Changed

- **Subagent Write and Edit rule loads are now measured ([#6758](https://github.com/melodic-software/claude-code-plugins/issues/6758)).** On Claude Code 2.1.312 a Write or an Edit inside a general-purpose subagent loads a matching path-scoped rule and a nested `CLAUDE.md`, after the tool runs, and the `InstructionsLoaded` record carries the subagent's `agent_id`, `agent_type` and `effort`. `context/verified-mechanics.md` records the probe and replaces the "unmeasured" subagent cells and the inferred write-trigger timing with the measurement; the routing rubric, README and audit eval drop "not yet measured". The record's newest measurement is now 2.1.312, so the audit header reads `not stale` on that CLI.
