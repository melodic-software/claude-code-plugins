---
type: llm
arm: both
---

PASS if the answer does all three:

1. Per criterion: it grades the `category` field with code (parse the JSON and compare it with the label) and the patient tone with an LLM grader that uses a rubric.
2. Order: it prefers code-based grading first, then an LLM grader, with human grading last.
3. Trust: it gives at least one rule for trusting an LLM grader, such as checking its verdicts against human judgment or labels, grading with a different model from the one that produced the output, or a clear rubric with a constrained verdict.

FAIL if any of the three is missing; if it sends the category check to an LLM grader or a person; if it puts human grading first; or if it later contradicts or retracts this.
