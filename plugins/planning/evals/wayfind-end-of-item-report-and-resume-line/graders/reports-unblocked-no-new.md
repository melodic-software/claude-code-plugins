---
type: llm
---

On map #200, the claimed item 'Choose the billing aggregate' (#42) just resolved to one Invoice aggregate per tenant, which unblocks 'Decide invoice numbering' (#44, https://github.com/acme/shop/issues/44), now the first frontier item; nothing new needs charting. The user asked to finish the item. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the reply says 'Decide invoice numbering' is now unblocked and that no new items were charted.

FAIL if either fact is missing.
