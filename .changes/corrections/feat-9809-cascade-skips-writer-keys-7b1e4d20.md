---
bump: patch
---

### Changed

- The config cascade skips the setup writer's top-level `written_against` and `provenance` keys, so
  neither reaches `values`, a layer's errors or a userConfig name.
