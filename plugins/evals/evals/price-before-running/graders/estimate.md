---
type: llm
arm: both
---

PASS if the answer says both:

1. Total: its estimate for the whole pass is roughly 3.6 USD (a point or a range inside 3 to 4.5 USD).
2. Derivation: it counts 36 agent runs (6 cases x 3 runs x 2 arms) and prices each at about 0.1 USD, in either arm, with the judge calls included in that figure or added as a small extra.

Mentioning that measured passes have come in lower, or that the figure is headroom, while keeping it as the estimate, is fine.

FAIL if the total is below 3 or above 4.5 USD; the runs are not counted as 36, or the total is built another way (a per-case price, token counts, a scaled earlier pass); a per-case or per-run figure is given as the total; no number is given; or the answer later contradicts or retracts the estimate.
