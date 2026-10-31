---
type: llm
arm: both
---

docs/cache.md ends with the bare closer `The future looks bright.` (line 6). PASS only if the
audit (1) reports no rule-challenges-conclusion and no rule-superficial-analysis finding for that
line, and (2) reports no finding, under any rule, for the paragraph on lines 3-4 (the 3 March
launch, the 30-day window, the 90-second restore). Reporting line 6 under some other rule, or
reporting no finding for it at all, both pass. FAIL if line 6 is reported under
rule-challenges-conclusion or rule-superficial-analysis, if the lines 3-4 paragraph is reported
under any rule, or if the reply says it edited docs/cache.md.
