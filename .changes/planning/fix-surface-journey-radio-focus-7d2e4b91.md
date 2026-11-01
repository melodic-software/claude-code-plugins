---
bump: patch
---

### Fixed

- The interview page keeps keyboard focus on a choice when a state push redraws the choices. Before, focus fell back to the page whenever Claude's next update arrived while a choice had focus, for example right after Answer again, so the arrow keys stopped moving between the choices.
