---
bump: minor
---

### Added

- **`explore-directions` builds prototypes for a shared interview.** For a `/planning:interview` shared session it writes the tiers the session offers (screenshots, one self-contained HTML snapshot per variant, a static live build) under the session's `staging/` folder, plus a `manifest.json` with a required where-to-look line, and keeps the in-page switcher only for prototypes of the interview page itself.
