---
bump: patch
---

### Changed

- `/performance:verify` now lists an untuned arm on its `Ruled out:` checklist: an arm left on default settings while the other was tuned. The verifier compares the settings each arm ran with, and when they differ it re-runs the default arm with the same tuning, because a gap that tuning only one arm produces belongs to the tuning, not the change. This comes from pstack's `explain-the-number` principle (`docs/upstream/cursor-pstack.md`).
