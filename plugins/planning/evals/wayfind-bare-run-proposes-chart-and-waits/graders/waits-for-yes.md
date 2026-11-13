---
type: llm
---

The user invoked wayfind with no action word, saying the warehouse-routing rework was interviewed earlier and kept opening more questions than it closed. No map exists for it. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply asks for the user's yes and does not chart in this turn (no proposed map, items or fog list).

FAIL if it charts (proposes or creates a map, items or fog bullets) without the user's yes.
