---
description: "deepening.md Phase 2: a runtime-claim Phase 1.5 reproduces as a live, non-security bug (a double fuel surcharge) is reported on its own before the candidate question, in the fallback report form since the bugs plugin is absent; a true dead-code claim is not reported as a defect. Hard: the defect sits inside a candidate's evidence, and the easy reply folds it into the card and moves on to the question. Source: written for this case from the deepening.md defect paragraph."
tags: [architecture, improve, deepening, defect-report, scaffold, hard]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Reproduces the double fuel surcharge from parcels/quote_service.py and parcels/rate_table.py, and before asking which candidate to explore names it as a defect of its own with a title, steps to reproduce (quote a 2 kg parcel to a zone B postcode), expected 6.75 against actual 7.50, and the file and function to fix; keeps it as evidence on the quote-path candidate; treats the LabelPrinter dead-code claim as not a defect; ends asking which candidate to explore."
---

/architecture:improve deepening --medium terminal

Phase 1 already ran on this repository; do not scan it again. You may read the files the scan names below, and this skill's own files. The scan returned two candidates:

1. Quote path (confidence: strong). Files: parcels/quote_service.py, parcels/zones.py, parcels/rate_table.py. shallow-signal: QuoteService.quote, ZoneLookup.zone_for and RateTable.price each do one step and hand on to the next, and the fuel surcharge rule sits in two of them. runtime-claim: live bug, a 2 kg parcel to a zone B postcode is quoted 7.50 where the rate card gives 6.75, because the fuel surcharge is added in both QuoteService.quote and RateTable.price.
2. LabelPrinter (confidence: worth-exploring). Files: labels/label_printer.py. runtime-claim: dead code, nothing imports it.

[The level reader has already been run for this request and printed `verification: standard (docs/conventions/architecture.yaml verification at origin/main)`; use that line and do not run the reader again.]

Carry on from Phase 1.5 through Phase 2. Write no files this time: put the candidate entries in your reply, and finish with the reply Phase 2 ends with.
