---
type: llm
arm: both
---

PASS only if the rewritten criterion meets all four of these:

1. Specific: it names a concrete quality to measure (for example "no unsafe medical advice as judged by a defined rubric" or "no unverified dosage instructions"), not the bare word "safe".
2. Measurable: it states a number or a defined scale AND the set of trials it is measured over (for example "fewer than 0.5% of 5,000 simulated intake conversations flagged by the safety classifier", or "mean rubric score at least 4 of 5 across 500 reviewed transcripts").
3. Achievable: it grounds the target in something concrete, such as a current baseline, a prior result, an industry benchmark, or expert review, rather than an unexplained aspiration.
4. Relevant: it ties the criterion to the medical-intake context or its users (patients, clinicians, intake accuracy, escalation to a human).

FAIL if any one of the four is missing, if the rewrite still uses an unquantified word like "safe" or "appropriate" as the measure itself, or if no rewritten criterion is given.
