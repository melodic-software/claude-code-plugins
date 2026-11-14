---
description: "deepening.md Phase 2: review-class problems the scan saw on a candidate (Any-typed parameters, an exception caught and discarded, a hard-coded tax rate) stay as evidence on that candidate, get no defect report, finding or badge of their own, and the reply names the owning skill or, with neither owning plugin installed, says they were seen and not assessed. Hard: the scan notes read like defects, and the easy reply turns each into a finding or bug report. Source: written for this case from the deepening.md review-class paragraph."
tags: [architecture, improve, deepening, review-class, scaffold, hard]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Reproduces the invoicing candidate's shallow-signal, keeps the Any-typed parameters, the discarded exception in InvoiceStore.save and the hard-coded 0.20 tax rate as evidence on that candidate only, reports no defect and adds no finding or badge for them, names /code-metrics:audit type-debt and /review:quality-gate code as their owners or says they were seen and not assessed, and ends asking which candidate to explore."
---

/architecture:improve deepening --medium terminal

Phase 1 already ran on this repository; do not scan it again. You may read the files the scan names below, and this skill's own files. The scan returned one candidate:

1. Invoicing path (confidence: strong). Files: invoicing/invoice_service.py, invoicing/tax_calc.py, invoicing/invoice_store.py, tests/test_invoice.py. shallow-signal: InvoiceService.issue, TaxCalc.apply and InvoiceStore.save each do one step and hand on to the next, and the test mocks the next hop. Also seen: every parameter and return in all three is typed Any; InvoiceStore.save catches every exception and discards it; TaxCalc.apply writes the 0.20 tax rate into the code.

[The level reader has already been run for this request and printed `verification: standard (docs/conventions/architecture.yaml verification at origin/main)`; use that line and do not run the reader again.]

Carry on from Phase 1.5 through Phase 2. Write no files this time: put the candidate entry in your reply, and finish with the reply Phase 2 ends with.
