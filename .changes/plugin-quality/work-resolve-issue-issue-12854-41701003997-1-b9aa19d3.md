---
bump: patch
---

### Fixed

- The context gate's copy of `scripts/context-zone.sh` now follows a lowered auto-compact window. When context-guard's snapshot carries `bands.auto_compact_window`, the resolver scales its percentage edges by that window over `context_window_size`, so the gate reads the same zone context-guard publishes (#12854).
