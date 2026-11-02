---
bump: patch
---

### Fixed

- The work-classes leaf now names the `provenance: signal` label as a third `C5` trigger, beside the fork and author-trust tests. An item carrying the label is `C5` whatever its `work-class:` label says, a class a routine run stamped included. The test reads the label, never the item body, and only a person with `write` removes the label. The guardrail contract's class list and the trigger-dispatch work-class section say the same, and the leaf notes that the babysit unattended merge gate's trust hold reads only `work-class: untrusted-provenance`, not `provenance: signal`.
