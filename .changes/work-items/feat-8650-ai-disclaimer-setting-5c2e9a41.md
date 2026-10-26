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
  `ai_disclaimer` resolves `true`; set it to keep the old behavior. A lane running on a person's
  own `gh` token, with no `lane_app_slug`, now posts model-written items and comments under that
  person's name with no AI marker at all; set `ai_disclaimer: true` there.
- **The work-loop objection window no longer treats an escalation's answer as a new objection.** A
  comment answers the newest work-loop escalation marker only when that marker is newer than the
  window comment, the comment comes before the autonomous-eligible role label was last applied,
  and its author is the trusted labeler who applied it. An attend-queue answer without the
  disclaimer does not re-escalate the item; any other comment in that span is still an objection.
