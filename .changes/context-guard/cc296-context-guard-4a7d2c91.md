---
bump: patch
---

### Fixed

- **The reader contract no longer describes the auto-compact window as one global setting.** Since Claude Code v2.1.288, `/autocompact` saves the window per model. The contract's tunable table stopped claiming a fixed count of surfaces, and now states our decision: the reader never resolves the window, so a per-model value it cannot see is treated like an unset one, and `zones.json` stays the correction path. A pointer record names the settings and model-config sections to read live. The README's summary of the tunables now points at that table instead of repeating the list. No behavior changed.
