---
bump: patch
---

### Fixed

- `block-cross-domain` now reads a flat worktree root listed in `owner_roots`. A name there that starts with an owner and a `-` (`<root>/<owner>-<repo>-<slug>`) is that owner's, in a command and for the session's directory, so a command naming another owner's flat worktree is denied. Of two listed owners the longest that fits holds the name, an owner no domain lists reads as the listed owner it starts with, another domain's root above the name is named as well, and a session's directory that a root or owner directory already holds stays with it, so the `-` only adds names and denies. A path now spends only the occurrences of its text that name it, so a longer name it merely starts stays for an outer root or a shorter owner to name. A tree whose name does not start with its owner stays outside the guard.
