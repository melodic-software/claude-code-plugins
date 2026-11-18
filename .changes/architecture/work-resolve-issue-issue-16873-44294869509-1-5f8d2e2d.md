---
bump: patch
---

### Changed

- The `improve` deepening action now gives the reason it never chooses the HTML report's location from an injected scratchpad path or `CLAUDE_JOB_DIR`: those directories belong to the harness's run, and the report must outlive the invocation at the path the secure temp-file primitive created. The `map-context` "Actors are not derived" gotcha states its own reason, that tracked configuration does not say who uses a system, in place of a paraphrase of the C4 system-context page ([#16873](https://github.com/melodic-software/claude-code-plugins/issues/16873)).
