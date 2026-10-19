---
bump: patch
---

### Fixed

- inventory: a built-in tool whose `aliases` array holds a spread the reader cannot follow now carries `aliases_source: partial` (or `unresolved` when the field is not an array literal) instead of an empty list. `--reader compare` then reports a regex/parser disagreement on such a list as `wrong->unresolved`, not a `value->value` change (#6888).
