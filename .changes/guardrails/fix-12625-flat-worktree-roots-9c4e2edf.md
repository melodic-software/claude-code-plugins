---
bump: patch
---

### Fixed

- `block-cross-domain` now reads a flat worktree root listed in `owner_roots`. A name there that starts with an owner and a `-` (`<root>/<owner>-<repo>-<slug>`) is that owner's, in a command and for the session's directory, so a command naming another owner's flat worktree is denied. Of two listed owners the longest that fits holds the name, and an owner no domain lists reads as the listed owner it starts with. A tree whose name does not start with its owner stays outside the guard.
