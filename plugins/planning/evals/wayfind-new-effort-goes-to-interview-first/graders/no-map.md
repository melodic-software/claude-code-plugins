---
type: llm
---

The user asked wayfind to chart a rewrite of the search indexing pipeline and said it has not been discussed at all yet; it just feels big. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply creates no map issue and no decision items.

FAIL if it creates or writes out a map issue or decision items.
