---
bump: minor
---

### Added

- A data source read with a credential names the credential's variable and a read-only `grants` command the consumer supplies; `/app-control:drive ready` runs it where the source's read level allows and reports the exit. A source with a credential and no passing `grants` record is capped at `attended`.
- A data source may record the data category it exposes, who may read it, and the review that decided both. `/app-control:map` asks for these, and for the credential fields, before it sets a read level above `never`; ready lists them.
