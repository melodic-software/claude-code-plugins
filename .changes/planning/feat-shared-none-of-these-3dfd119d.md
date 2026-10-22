---
bump: minor
---

### Added

- On the shared interview page, a pick-any question can offer "None of these": Claude asks for it with `none: true` on a `multi` format, the server adds the option and refuses a Claude-written one, it excludes every other pick (picking it clears them, picking another clears it), and the digest counts it as its own row, apart from a Pass or an empty pick.
