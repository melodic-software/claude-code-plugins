---
type: llm
---

The user invoked wayfind with only an issue link, https://example.com/acme/shop/issues/43. A tracker export in the workspace shows it is 'Choose the cart persistence model', an open, unassigned, unblocked item labeled 'wayfind: design' on map #40 'Map: checkout redesign'. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply claims the linked item before routing it by its type label (design), or reports why the item is off the frontier.

FAIL if it routes without claiming, claims nothing and gives no off-frontier reason, or routes by something other than the type label.
