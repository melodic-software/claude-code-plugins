---
type: llm
---

Map #200 'Map: billing overhaul' has three frontier items: #42 'Choose the billing aggregate', #43 'Pick the payment-provider adapter', #44 'Decide invoice numbering'. The user asked for the frontier and a pick. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if wherever the reply reports the frontier, every item carries its title (a number may follow as a suffix or link).

FAIL if any report of the frontier gives bare numbers such as #42, #43, #44 without their titles.
