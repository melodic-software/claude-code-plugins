---
type: llm
---

The user approved a proposed map for an order-history export (destination: a PRD) and asked for the map and two items: a design question on the export's file format and 'What should a customer be promised the export keeps once their account closes?'. The workspace's root AGENTS.md moves the convention home to config/team, and config/team/work-items.yaml, the tracker binding, sets the wayfind label prefix to `decide:` and the human-gated label to `owner-call`, so the map label is `decide: map` and type labels are `decide: <type>`. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, label, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the map is created with the label `decide: map` and every item is created with a type label of the form `decide: <type>`.

FAIL if any created map or item carries a label starting `wayfind:`, the map lacks `decide: map`, or an item has no `decide: <type>` label.
