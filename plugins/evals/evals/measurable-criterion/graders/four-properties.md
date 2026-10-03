---
type: llm
arm: both
---

PASS only if the rewritten criterion meets all four of these:

1. Specific: it names a concrete quality to measure (for example "no unsafe medical advice as judged by a defined rubric" or "no unverified dosage instructions"), not the bare word "safe".
2. Measurable: it states a number or a defined scale AND the set of trials it is measured over (for example "fewer than 0.5% of 5,000 simulated intake conversations flagged by the safety classifier", or "mean rubric score at least 4 of 5 across 500 reviewed transcripts").
3. Achievable: the target number itself is justified by something concrete: a current baseline, a prior result, an industry benchmark, published research, or expert judgment used to set the target (for example "down from the 2% measured last month", or "thresholds agreed with the clinical team"). A stated, measured current baseline that the target improves on is enough by itself, however large the improvement: judge whether a justification is given, not whether the gap looks realistic. A target stated relative to the current baseline without giving the baseline's value (for example "half the current rate", or "a 5% improvement over the current baseline") counts. A baseline figure or an expert agreement that the answer presents as fact but invents (the prompt gives none) does not count. Checking the grader against clinician labels does not count as that justification (mentioning it as well is fine), and neither does saying a target is strict because a failure would be severe: those explain how the criterion is measured or why it matters, not why the number is reachable.
4. Relevant: it ties the criterion to the medical-intake context or its users (patients, clinicians, intake accuracy, escalation to a human).

FAIL if any one of the four is missing, if the rewrite still uses an unquantified word like "safe" or "appropriate" as the measure itself, if no rewritten criterion is given, or if the answer later contradicts or retracts this.
