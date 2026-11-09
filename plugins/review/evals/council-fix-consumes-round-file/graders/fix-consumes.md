---
type: llm
arm: both
---

PASS if the answer says fix applies the council's findings by admitting the round file (`-council-r1.md`), because it is a `type: review-findings` file for this branch in fanout's findings location and shape, and that fix does not read the run file (`-council.md`) as findings because its type is `council-run`, not review-findings.

FAIL if the answer says fix cannot read council output, needs a conversion step, reads the run file as findings, or reads both files as findings.
