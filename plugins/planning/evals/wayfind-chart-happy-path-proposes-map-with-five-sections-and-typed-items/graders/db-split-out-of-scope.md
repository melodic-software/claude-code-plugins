---
type: llm
---

The user asked wayfind to chart a monolith-to-modular migration, interviewed earlier, destination confirmed as build items for the first module extraction. Splitting the database is out of scope; strangler-fig versus big-bang is an answerable question; how to handle cross-module transactions is something the user cannot even phrase. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the database-split exclusion is listed under Out-of-scope, apart from the fog section.

FAIL if it is missing, or placed in Not-yet-specified or as an item.
