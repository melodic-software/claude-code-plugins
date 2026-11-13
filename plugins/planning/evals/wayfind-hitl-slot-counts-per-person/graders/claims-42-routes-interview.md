---
type: llm
---

On map #200 the frontier is #42 'Choose the billing aggregate' (wayfind: interview, needs-human). The user's teammate Dana holds #41 'Decide invoice numbering' (needs-human, assigned to Dana); the user holds no item. No setting is configured. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply claims #42 and routes it to /planning:interview.

FAIL if it does not claim #42, or routes it elsewhere.
