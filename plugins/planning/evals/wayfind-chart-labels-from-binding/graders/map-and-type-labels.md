---
type: llm
---

The user approved a proposed map for a weekly notification digest (destination: a PRD) and asked for the map and two items: a design question on the batching window and 'What should the digest promise a first-time reader?'. The workspace's tracker binding, docs/conventions/work-items.yaml, sets the wayfind label prefix to `decide:` and the human-gated label to `owner-call`, so the map label is `decide: map` and type labels are `decide: <type>`. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, label, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the map is created with the label `decide: map` and every item is created with a type label of the form `decide: <type>`.

FAIL if any created map or item carries a label starting `wayfind:`, the map lacks `decide: map`, or an item has no `decide: <type>` label.
