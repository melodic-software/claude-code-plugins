---
bump: minor
---

### Changed

- Intake admission posts an admission record (a new lanes-App comment with the sha256 of the issue title and body it admitted) before it sets the Work status to agent-ready. The issue lane freezes a run's text at the newest admission record or a listed human's agent-ready Work status set, at or before the event that started the run, instead of at an agent-ready label event, and refuses a run whose title or body no longer matches the record's hashes.
