---
type: llm
arm: both
---

PASS only if the audit reports the sentence `Some critics argue that a log-based queue is overkill
for a service this size.` (docs/queue.md line 11) under rule-vague-attribution, quoting some of its
words. FAIL if that sentence gets no finding, or is reported only under a different rule.
