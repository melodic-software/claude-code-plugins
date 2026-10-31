---
type: llm
arm: both
---

PASS only if the audit (1) reports the sentence beginning `Experts argue` (it also says the
choice is `widely regarded as the modern default`) under rule-vague-attribution, quoting some of
its words, and (2) reports no rule-vague-attribution finding for the second paragraph, which
gives the March load-test figures (40,000 and 12,000 messages a second) and quotes the Kafka
documentation. A sentence saying the second paragraph is properly sourced is fine. FAIL if the
weasel sentence is not reported under rule-vague-attribution, if the second paragraph is
reported under rule-vague-attribution, or if the reply says it edited docs/queue.md.
