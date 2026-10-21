---
bump: minor
---

### Added

- `/debugging:debug` Phase 2 gains a Minimize step: cut inputs, callers, config, data and steps one at a time, keep a cut only when the loop stays red, and stop when every remaining element is needed. The Phase 3 gate now requires the minimized reproduction.
- `/debugging:debug` Phase 5 step 2 asks for a diff against a pristine copy when the red was forced by editing code or a fixture, to confirm the edit landed before the red is trusted.
- `/debugging:debug` notes that every answer the human-driven script collects with `ask` is pasted back into the session, so it asks only for observations and leaves signing in to an `instruct` step.
