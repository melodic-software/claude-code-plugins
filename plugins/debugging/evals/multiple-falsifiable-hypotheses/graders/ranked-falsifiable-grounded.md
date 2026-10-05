---
type: llm
---

PASS if, before testing any single hypothesis, the reply lists between 3 and 5 hypotheses in a ranked order, each one stating a prediction (what change would make the crash disappear or get worse if it were the cause), and the ranking draws on real repository state such as recent commits in the exporter, ADRs, or known-issues notes (or says it will check them before ranking).

FAIL if the reply gives one or two hypotheses, more than five, hypotheses with no predictions, or a ranking with no reference to repository state, or starts testing or fixing one cause before listing the set.
