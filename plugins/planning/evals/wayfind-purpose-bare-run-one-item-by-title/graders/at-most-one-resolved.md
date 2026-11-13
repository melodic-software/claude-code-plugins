---
type: llm
---

The user invoked wayfind with no action word. One map is open, 'Map: billing overhaul' (#200), with frontier items 'Choose the billing aggregate' (#42), 'Pick the payment-provider adapter' (#43) and 'Decide invoice numbering' (#44). The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply resolves (posts a resolution for, or closes) at most one item.

FAIL if it resolves or closes two or more items.
