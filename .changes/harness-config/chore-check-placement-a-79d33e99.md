---
bump: patch
---

### Changed

- `audit-automation-gaps` no longer recommends a per-edit `PostToolUse` hook for a report-only check and flags an existing one with its placement: a git `pre-commit` hook on changed lines, `pre-push` up to 60 s, CI beyond. Formatters are recommended once per batch (`PostToolBatch`) within a 1 s median per fire, and at `pre-commit`. The shift-left carve-out's second conjunct now requires that placement, where it used to accept an advisory per-edit hook.
- `audit-instructions`' `PostToolUse` worked example places the actionlint check in a git `pre-commit` entry.
