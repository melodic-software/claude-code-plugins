---
bump: patch
---

### Fixed

- On an unanswered question, the interview page shows "Details: what we know, alternatives" open,
  whatever `moreOpen` value the browser stored. The facts and alternatives a decision rests on are
  in view on first load. If you close Details on a question, it stays closed there until the page
  reloads. An answered question still follows the stored `moreOpen` value.
