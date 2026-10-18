---
bump: patch
---

### Fixed

- `/fleet:reach` no longer says an interactive session simply accepts inbound messages: it holds one from a sender that bypasses permission prompts, and a `-p` receiver without `crossSessionInbound: accept` drops a held message after `dialogExpiry`.
- The relay reference's agent view note now names the `#limitations` anchor, an as-of date and a recheck trigger.
