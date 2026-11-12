---
bump: patch
---

### Changed

- Corrected in place: the released entries [0.1.0], [0.3.0], [0.7.11], [0.7.19], [0.7.21], [0.13.6], [0.13.8], [0.13.9], [0.14.7], [0.18.10] now name the context-usage plugin by its current name.
- References to the context-window plugin use its new name, context-usage: the `/context-usage` commands, the `mcp__context-usage__status` tool and the `~/.claude/context-usage/` directory.
- The vendored zone resolver reads `~/.claude/context-usage/`, falling back to the directory the plugin used before its rename while a session started before the update still writes there; it reads `zones.json` from `~/.claude/context-usage/`, else from the directory the plugin used before its rename.
- The audit's compaction override also honors a session's marker in the directory the context plugin used before its rename.
