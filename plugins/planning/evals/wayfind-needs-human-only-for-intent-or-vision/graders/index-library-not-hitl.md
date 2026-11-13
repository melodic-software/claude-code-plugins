---
type: llm
---

The user approved a proposed map for a search rewrite (destination: build items) and asked for two items: 'Which index library meets the 50 ms p95 budget we already set?' (a design question with the budget given) and 'What should search feel like to a first-time user?'. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the index-library item is created without the needs-human label.

FAIL if it carries needs-human.
