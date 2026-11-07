---
bump: minor
---

### Added

- `retro_offer` option (`offer` or `off`, default `offer`): under `off`, `/session-flow:workflow wrap-up` offers no retrospective, including the `/session-flow:retro` fallback for a session with errors; `/corrections:codify` is still suggested, since it is not a retro (#7555).
