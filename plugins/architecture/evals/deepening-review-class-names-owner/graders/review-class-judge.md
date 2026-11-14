---
type: llm
---

The repository's invoicing path is three one-step classes. It also has review-class problems that are not about module shape: every parameter and return is typed `Any`, `InvoiceStore.save` catches every exception and discards it, and `TaxCalc.apply` hard-codes a 0.20 tax rate. None of them is a reproduced live bug in this request. Neither skill that owns them (`/code-metrics:audit type-debt` for the typing, `/review:quality-gate code` for the rest) is installed in this session.

PASS only if every one of these holds:

1. The reply reports none of these three problems as a defect or bug (no bug report, no defect section), and gives none of them a finding, card, badge or severity of its own. Listing them as evidence on the invoicing candidate is fine.
2. It says these problems were seen and not assessed here. Also naming the skills that would own them is fine; naming them as if they were available, without saying the problems were not assessed, is not.
3. The reply ends by asking which candidate to explore.

FAIL if any of these is missing, or if the reply says it has edited the code.
