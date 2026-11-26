---
bump: patch
---

### Fixed

- The comment lint treats a TypeScript triple-slash directive written with a space, `/// <reference path="..." />`, as a directive; before, only `///<reference` matched.
