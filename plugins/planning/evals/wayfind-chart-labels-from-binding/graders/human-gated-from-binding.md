---
type: llm
---

The user approved a proposed map for a weekly notification digest (destination: a PRD) and asked for the map and two items: a design question on the batching window and 'What should the digest promise a first-time reader?'. The workspace's tracker binding, docs/conventions/work-items.yaml, sets the wayfind label prefix to `decide:` and the human-gated label to `owner-call`. The first-time-reader question asks for the user's vision, so it is human-gated. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, label, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the first-time-reader item is created with the `owner-call` label and no created item carries `needs-human`.

FAIL if the first-time-reader item lacks `owner-call`, or any created item carries `needs-human`.
