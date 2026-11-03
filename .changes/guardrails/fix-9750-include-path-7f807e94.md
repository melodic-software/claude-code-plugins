---
bump: patch
---

### Fixed

- deny a global git include.path write in block-cross-domain

  An unconditional include can set the machine's git identity just as an
  includeIf does, and the guard let `git config --global include.path`
  through. It now treats the key and the include section as identity writes.
