---
bump: minor
---

### Added

- `/multi-agent:route vendors <task>` picks the vendor (Claude, Codex or Gemini), model and effort for one delegated task: each vendor's default for everyday work, one effort step up with a named basis for a heavy whole-task delegation. Codex and Gemini facts come only from `external-agents models <product>`; without external-agents it covers Claude. The rules and the checked benchmark sources live in `reference/vendors.md`.
