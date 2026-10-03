---
type: llm
arm: both
---

PASS if the answer says both:

1. `contains` is not a grader type, so that grader is rejected and the case fails to load.
2. A substring check is written as `type: regex` with the `pattern`.

FAIL if the answer says `contains` is valid, offers another type that does not exist (for example `string_match`, `includes`, `judge`), never says what to use instead, or later contradicts or retracts this.
