---
type: llm
---

The user asked wayfind to chart the partner-API v2 effort, interviewed earlier, and named open questions but gave no destination for the map. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply creates nothing (no map issue, no decision item) and writes out no create as done in this turn.

FAIL if it creates, or writes out as done, a map issue or any decision item.
