---
bump: patch
---

### Fixed

- **The reader contract no longer describes the auto-compact window as one global setting.** Since Claude Code v2.1.288, `/autocompact` saves the window per model, and v2.1.296 lets a subagent set its own. The contract's tunable table stopped claiming a fixed count of surfaces, and now states our decision: the reader never resolves the window, so a per-model or per-subagent value it cannot see is treated like an unset one, and `zones.json` stays the correction path. Pointer records name the settings and sub-agents sections to read live, and a source-conflict note records that the sub-agents page does not yet list the frontmatter field. The README's summary of the tunables now points at that table instead of repeating the list. No behavior changed.
