---
bump: patch
---

### Changed

- `/discovery:explore` and `/discovery:research` `## Next` sections send work whose diff will not be quick to review and cheap to retry to `/planning:interview` when no contract is locked, and hold one successor per bullet; explore drops `/discovery:trace-intent` and `/planning:plan`, research drops `/discovery:read-docs`, `/discovery:trace-intent` and `/planning:plan`. `/discovery:explore`, `/discovery:research` and `/discovery:blindspot` name `/session-flow:workflow` for a session unsure where it stands.
