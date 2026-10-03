---
type: llm
arm: both
---

PASS if the answer says this target (a whole plugin against a no-plugin baseline) is scaffolded by `claude plugin eval init`, which interviews for the cases and graders and writes them in the layout its runner reads, rather than the cases being hand-written here.

FAIL if the answer writes the case files itself as the main answer, uses the skill-creator `evals.json` format, puts the full SKILL.md text into the prompt as the "with" arm, or later contradicts or retracts this.
