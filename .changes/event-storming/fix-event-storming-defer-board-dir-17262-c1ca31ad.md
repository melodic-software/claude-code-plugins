---
bump: patch
---

### Fixed

- A simulation on the markdown backend no longer runs shell commands before its first reply: the
  board directory and the backend check resolve just before the first board write, and the first
  reply names markdown as the default and `docs/event-storming` as the board directory.
