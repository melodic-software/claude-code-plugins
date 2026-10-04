---
type: llm
---

The repository holds one module, `tax`, whose only public entry point is `compute_tax(order)`; the rate tables, exemptions and rounding sit in private files behind it, the tests call only `compute_tax`, and an ADR keeps the rules in-process. `invoice.py` is a thin command-line caller.

PASS if every one of these holds:

1. The reply states that the scan found no deepening candidate (or no shallow module worth deepening) in this repository.
2. The reply presents no module as a recommended candidate: no card or numbered candidate with a Strong or Worth exploring badge, and no proposed new interface for `tax`.
3. Any module the reply mentions is described accurately (for example, `tax` as already deep, `invoice.py` as a thin caller), not as shallow.

FAIL if the reply lists one or more candidates to deepen, proposes splitting or wrapping `tax`, calls `tax` shallow, or ends by asking which candidate to explore when it named none.
