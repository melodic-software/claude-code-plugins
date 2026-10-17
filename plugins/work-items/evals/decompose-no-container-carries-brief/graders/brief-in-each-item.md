---
type: llm
---

The workspace holds an approved PLAN.md whose Brief states a Goal (finance staff reconcile refunds
against the bank statement each month without asking engineering for a database query) and two
Constraints (the nightly ledger job's schedule and output stay untouched; the export reads only from
the reporting replica, never the primary database). Neither appears in the two plan phases. The user
approved plain items with no spec container.

PASS if every item body the run published carries that Goal and both Constraints as text, in the
item body itself, and no item body names a `.work/` path or links the PLAN.md file.

FAIL if any published item body omits the Goal or either Constraint, points at the plan file instead
of carrying the text, names a `.work/` path, if the run published a spec container instead of plain
items, or if it published nothing.
