---
bump: patch
---

### Fixed

- The comment lint judges a comment line whose only change is a renamed identifier like the unchanged line, so it no longer fails. The line must replace a removed line of the same hunk word for word except for identifier-shaped words (holding `_`, a digit, or a lower-to-upper case change), each renamed one way across the hunk. A comment whose prose words changed, or a plain-word swap, is still judged as new.
