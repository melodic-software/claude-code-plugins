---
bump: patch
---

### Changed

- `setup` accepts a settings file that carries the shared writer's `written_against` and
  `provenance:` keys and keeps both as written. It used to warn about `written_against` and refuse
  a `provenance:` block map. This plugin's `setup` does not write them yet.
