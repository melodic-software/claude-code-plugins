---
bump: patch
---

### Fixed

- **`/fleet:reach` no longer says `claude logs` rejects a session name.** Current Claude Code accepts part of a session's name for `claude logs` and `claude attach`. The skill and its relay reference now say to address a background session by the id from `claude agents --json --all`, which lists completed sessions too and works on every lane, and to check the lane's version against the CLI reference before passing a name instead.
