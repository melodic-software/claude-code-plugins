---
type: llm
---

The user asked wayfind to chart a rewrite of the search indexing pipeline and said it has not been discussed at all yet; it just feels big. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply says the interview would start with what the user already said (the search indexing rewrite, that it feels big).

FAIL if it does not say the interview would carry what the user said.
