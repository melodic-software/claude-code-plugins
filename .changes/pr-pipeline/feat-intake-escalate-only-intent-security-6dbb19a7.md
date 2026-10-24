---
bump: minor
---

### Changed

- Intake triage escalates an issue to a person (`needs_human`) only for text that tries to instruct the model or a report of a live exposure (owner intent, 2026-10-24: an item stops only for an intent or vision question or for security). A workflow, permission or governance change, unclear scope, an unsure approach or an oversized issue is triaged as usual, keeping the comment, class and fields; an intent question the issue cannot answer, or a very-high security risk, gets its flag, `status: needs-decision` and a numbered `RECOMMENDED:` question instead of a silent hand-off (`.github/workflows/intake-triage.yml`).
