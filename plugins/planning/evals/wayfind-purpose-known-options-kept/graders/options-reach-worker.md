---
type: llm
---

The user asked wayfind to chart an order-search effort (destination: a PRD). One open question, which search backend to use, comes with three known options: Postgres full-text search, OpenSearch, Typesense. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if all three options (Postgres full-text search, OpenSearch, Typesense) are written into the backend item (title, body or criteria) or into another tracker place the output says the item's worker reads (for example the map's Notes or a seed item's resolution comment).

FAIL if any of the three options appears only in chat or nowhere, so the item's worker would not see it.
