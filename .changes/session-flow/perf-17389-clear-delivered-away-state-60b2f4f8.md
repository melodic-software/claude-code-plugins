---
bump: patch
---

### Changed

- clear a delivered absence's away state

  deliver now removes the session's away state and then away/ itself
  when it is empty, so the away hooks' shell gate exits before Python
  again in later sessions. A report kept inside the state dir moves to
  <plugin data>/away-reports/ first, and deliver prints where it lasts.
