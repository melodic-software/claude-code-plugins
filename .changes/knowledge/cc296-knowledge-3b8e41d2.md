---
bump: patch
---

### Fixed

- **docpage-digest's Agent-tool fallback now sets the verifier's effort.** Where the Workflow tool is unavailable, Phase 4 dispatches verifier A through the Agent tool and now passes `effort` on that call on the same terms as the Workflow call, instead of accepting whatever the agent's pin or the session level happened to be. The skill no longer says the Agent tool takes no per-call effort, which stopped being true in Claude Code 2.1.292, and both places now point at the subagents docs section on effort for the live precedence.
