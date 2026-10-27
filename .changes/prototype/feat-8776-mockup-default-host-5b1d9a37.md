---
bump: minor
---

### Changed

- `/prototype:explore-directions` builds its variants as a self-contained HTML mockup by default, so whoever decides opens one `file://` page with nothing running. The real stack (sub-shape A, or B when no page can host the variants) is an explicit override, chosen only when the person asks for the variants on the real stack or in the app, and stays where the winner is folded in; the skill suggests it when the judgment depends on live data volume or page chrome the mockup cannot rebuild. The description, Purpose, intent selector, boundary sections, README and `docs/native-surfaces` rows now name the mockup as the default host. New evals cover the default, the default with a dev server running, and the real-stack override.
