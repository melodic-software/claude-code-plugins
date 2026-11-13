---
type: llm
---

The user invoked wayfind with only an issue link, https://github.com/acme/shop/issues/43. A tracker export in the workspace shows it is 'Choose the cart persistence model', an open, unassigned, unblocked item labeled 'wayfind: design' on map #40 'Map: checkout redesign'. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply does not propose charting a new map.

FAIL if it proposes charting a new map.
