---
bump: major
---

### Changed

- **`/session-flow:show-options` is now `/session-flow:recommend-skills`.** The old name no longer resolves; invoke the skill by its new name. Its Spotlight ledger moved with it, to `<memory_dir>/recommend-skills/spotlight-ledger.json`, so the rotation starts over once. Update anything that still names `session-flow:show-options`: saved prompts (routines, scheduled tasks, `/loop`), `Skill(...)` permission rules and `skillOverrides` entries. A deny rule or an off override on the old name does not cover the new one.
