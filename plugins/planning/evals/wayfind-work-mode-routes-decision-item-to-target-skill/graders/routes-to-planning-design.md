---
type: llm
---

The user ran work mode on map #142; the next open, unblocked, unassigned item is #145, labeled 'wayfind: design', asking to choose the aggregate boundaries for a new billing domain. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply routes the aggregate-boundary decision to /planning:design (invoking it, or writing the call it would make) and does not settle the boundaries itself.

FAIL if it settles the aggregate boundaries itself as the decision, routes the item to any skill other than /planning:design, or routes it nowhere.
