---
type: llm
---

The user asked wayfind to chart a 'forgot password' email flow and said it is exactly three clear tickets: a reset-token request endpoint, an email send, and a reset-confirmation endpoint. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply says the three pieces are already sharp, answerable tickets rather than fog.

FAIL if it treats the work as foggy or never says it is already sharp.
