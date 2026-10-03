---
type: llm
arm: both
---

PASS if the answer says both:

1. The +0.25 counts as a gain only when the noise report's verdict says the interval excludes 0.
2. A `within noise` or `n too small to call` verdict means the gain is not established.

FAIL if the answer says to post the +0.25 whatever the noise verdict; treats a positive delta as established without the noise report; makes another test (a t-test, a bootstrap, a second run) the deciding check; or later contradicts or retracts this.
