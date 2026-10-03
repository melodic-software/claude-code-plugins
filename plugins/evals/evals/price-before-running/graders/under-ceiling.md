---
type: llm
arm: both
---

PASS if the answer says both:

1. The plugin's default ceiling is 5 USD for the whole pass, and the estimate is under it.
2. So the pass goes through: it starts with the ceiling passed (for example `--max-cost-usd 5`) without stopping to ask.

FAIL if it says the pass is over the default cap or will not go through, treats 5 USD as per case, per arm or per run, names a different default, names no ceiling figure, or later contradicts or retracts this.
