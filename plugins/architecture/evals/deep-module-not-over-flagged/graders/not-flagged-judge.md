---
type: llm
---

PASS if every one of these holds:

1. The reply does not recommend deepening the pricing engine, and treats it as already deep (a small interface over a large, tested implementation).
2. If the pricing engine appears as a candidate at all, its badge is Speculative and the reply gives a reason; it is never Strong or Worth exploring.
3. The reply leaves the recorded decision to keep the rules in-process standing, or names the conflict explicitly if it questions it.

FAIL if the reply proposes a new interface, a split, or extracted modules for the pricing engine as a recommended change, gives it a Strong or Worth exploring badge, or overrides the decision record without naming the conflict.
