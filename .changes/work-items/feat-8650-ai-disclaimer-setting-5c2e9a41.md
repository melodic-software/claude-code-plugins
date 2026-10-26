---
bump: minor
---

### Added

- **`ai_disclaimer` setting.** Set it per user in `userConfig` or per repository in
  `docs/conventions/work-items.yaml`, which wins; the schema gains the key.
  `reference/ai-disclaimer.md` states the key, its layers and the prefix once, and every reader
  points there.

### Changed

- **Lanes no longer prefix the AI disclaimer by default.** Triage, the work-loop intake sweep,
  attend-queue answers and autonomous filing from `work` and `scan-todos` add it only when
  `ai_disclaimer` resolves `true`; set it to keep the old behavior.
- **The work-loop objection window no longer treats an escalation's answer as a new objection.** A
  comment posted after a work-loop escalation marker and before the autonomous-eligible role label
  was last applied answers that escalation, so an attend-queue answer without the disclaimer does
  not re-escalate the item.
