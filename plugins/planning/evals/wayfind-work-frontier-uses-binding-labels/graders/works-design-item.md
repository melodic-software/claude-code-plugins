---
type: llm
---

The user ran wayfind's work mode unattended. The workspace's tracker binding, docs/conventions/work-items.yaml, sets the human-gated label to `owner-call` and the wayfind prefix to `decide:`. A tracker export shows one open map, #60 'Map: notification digest' (label `decide: map`), with two open, unassigned, unblocked items in creation order: #61 'Decide what the digest promises a first-time reader' (labels `decide: interview`, `owner-call`) and #62 'Pick the digest batching window' (label `decide: design`). The sandbox has no tracker, so the reply writes out each tracker action it would take (create, label, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply claims #62 and routes it to /planning:design.

FAIL if it does not claim #62, routes it elsewhere, or stops reporting that every remaining decision needs a human.
