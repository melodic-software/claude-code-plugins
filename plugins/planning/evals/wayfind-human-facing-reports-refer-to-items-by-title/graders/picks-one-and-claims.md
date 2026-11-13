---
type: llm
---

Map #200 'Map: billing overhaul' has three frontier items: #42 'Choose the billing aggregate', #43 'Pick the payment-provider adapter', #44 'Decide invoice numbering'. The user asked for the frontier and a pick. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply picks one frontier item and claims it (a /work-items:track start call, or assignee plus a claim comment) before routing it, without resolving all three inline.

FAIL if it claims nothing, routes before claiming, or resolves several items itself.
