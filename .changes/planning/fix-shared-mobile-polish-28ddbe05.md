---
bump: minor
---

### Added

- Shared interview: a problem report carries up to four screenshots in its first send, picked several at once, pasted or added one by one; the host opens each with its own Show screenshot.
- Shared interview: the host's Approve all in Proposed makes every waiting proposal a question in the next round, behind a confirm that names how many.

### Fixed

- Shared interview: every round in the question rail shows a check or an empty ring in one slot, so the round labels line up.
- Shared interview: on a phone, the question header keeps the purpose and Ask someone together on one row of 44 px targets.

### Security

- Shared interview: a request from someone not joined is refused with 401 from its headers, before the server reads its body, so a larger problem report cannot hold the server for its upload time.
