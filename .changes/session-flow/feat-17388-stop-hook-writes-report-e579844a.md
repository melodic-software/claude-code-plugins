---
bump: minor
---

### Changed

- step-away: during an absence the Stop hook rewrites the away report's refused-actions and external-actions blocks itself, so the session no longer runs `away.py refresh` from a Bash command, which the Bash sandbox kept from writing the state. The watched-folder file scan still runs at `end` and on `refresh --files`.
