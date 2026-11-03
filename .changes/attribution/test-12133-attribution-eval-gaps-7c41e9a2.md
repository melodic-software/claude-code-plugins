---
bump: patch
---

### Changed

- `/attribution:setup`: the YAML form, per-key notes, eval-fixture exclusion and trigger-less enable test move from the skill body to `skills/setup/reference/keys.md`, which the body says to read before a `check` interview or proposed change, before `apply` writes a key, and when asked what a key does. No rule changes.
- The `audit-*` eval cases load an eval-only `review` stand-in, so the producer contract resolves inside the sandbox and two cases grade that a findings file was written. Both `setup check` cases fail a command that removes or moves `.claude/provenance.json`.
