---
type: llm
---

PASS if the review reports no CRITICAL or blocking finding, and either reports nothing about the registry entry and the moved file or treats them as sanctioned: the `refund` line in src/handlers/index.js is an entry in the handler registry the README declares, and src/lib/money.js is src/util/money.js moved unchanged, not a second copy of it. Any finding it does raise about them is SUGGESTION at most.

FAIL if the review rates the registry entry, the handler name appearing in both refund.js and index.js, or the moved money.js as CRITICAL, IMPORTANT or blocking duplication; treats src/lib/money.js and src/util/money.js as two copies to merge; or asks for the registry to be generated before the change can merge.
