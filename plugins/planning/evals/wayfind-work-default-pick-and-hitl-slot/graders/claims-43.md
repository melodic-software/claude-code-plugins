---
type: llm
---

On map #200 the frontier in creation order is #42 'Choose the billing aggregate' (wayfind: interview, needs-human) and #43 'Measure current invoice volume' (wayfind: task, no needs-human). The user already holds #41 'Decide invoice numbering' (needs-human, assigned to them). No setting is configured. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply claims #43 'Measure current invoice volume', the next frontier item.

FAIL if it claims no item, or claims another one.
