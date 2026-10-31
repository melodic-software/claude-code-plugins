---
bump: patch
---

### Fixed

- The convention-home resolver refuses a pointer that names `.git` or a path inside it, and a
  working-tree home reached through a symlink: both exit 3.
