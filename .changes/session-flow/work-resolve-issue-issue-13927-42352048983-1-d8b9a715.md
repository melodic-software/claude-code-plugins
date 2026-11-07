---
bump: patch
---

### Fixed

- The handoff skill and its structure reference now match `save_point.py validate`. A rule or preference that leaves the hot file is listed in this hop's file under `## Retired rules` with a reason, and none leaves to meet the size cap. A file whose core alone, or core plus carried content, is over the hot-file cap passes `validate` with an `UNVALIDATED` warning and is emitted as it stands, not shortened, up to the Read page cap (#13927).
