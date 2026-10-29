---
bump: patch
---

### Changed

- Shared `transcript_reader.py` synced where this plugin carries it: it gains
  `iter_workflow_agents`, which this plugin does not call; `iter_subagents` is unchanged.
