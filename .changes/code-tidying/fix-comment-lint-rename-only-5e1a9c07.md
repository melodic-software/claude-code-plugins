---
bump: patch
---

### Fixed

- The comment lint judges a comment line whose only change is a renamed identifier like the unchanged line, so it no longer fails. The line must replace a removed line of the same hunk word for word except for identifier-shaped words (holding a letter and `_`, a digit, or a lower-to-upper case change), each renamed one way across the hunk. A comment whose prose words changed, a plain-word swap, or a changed number (such as `ADR-0042` to `ADR-0999`) is still judged as new.
