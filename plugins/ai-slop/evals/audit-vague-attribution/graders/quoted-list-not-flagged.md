---
type: llm
arm: both
---

The last paragraph of docs/queue.md (lines 13-15) names two outlets, and each carries what it
said: InfoQ's case study with its lag and throughput figures, and the Confluent blog post with a
quoted line. PASS only if the audit reports no rule-vague-attribution finding for that paragraph.
Saying the paragraph is properly sourced, or that each outlet carries its finding or quote, is
fine. FAIL if any rule-vague-attribution finding points at that paragraph or quotes `InfoQ`,
`Confluent` or `Two write-ups covered the switch`.
