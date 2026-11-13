---
type: llm
---

On map #500, the claimed task item #507 'Set up the Knock sandbox account' needs someone to sign up in Knock's dashboard and create an API key; the user will do it. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the resolution, drafted or described, records the names and locations of what was set up (the Knock sandbox account, the API key's name and where it is stored).

FAIL if it records no names or locations of what was set up.
