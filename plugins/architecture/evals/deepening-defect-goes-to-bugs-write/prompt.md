---
description: "deepening.md Phase 2 with a bugs plugin loaded beside architecture: a runtime-claim Phase 1.5 reproduces as a live, non-security bug (a double fuel surcharge) goes to /bugs:write with --file, is named before the candidate question, and nothing is filed in a tracker. A stand-in (bugs-stub/, the write skill's name and --file contract only) loads so /bugs:write is in the skill list: the CLI loads a second plugin only from inside the case directory. So the case measures that the scan routes the defect to /bugs:write --file; what the real skill does with --file is not measured here. The without-arm loads neither plugin, so the Skill grader (arm: both) fails there by construction, and the with-arm pass count is the measure. Hard: the installed path composes two skills, and the filing offer must stay an offer. Source: written for this case from the deepening.md non-security bullet; same scaffold as deepening-defect-reported-on-its-own. Needs --scaffold --allow-tools Bash and a sandbox backend."
tags: [architecture, improve, deepening, defect-report, bugs-plugin, scaffold, hard]
plugins: ["../..", "bugs-stub"]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Reproduces the double fuel surcharge, invokes /bugs:write with --file for it (filing offered, not done), names the defect before asking which candidate to explore, runs no gh issue or pr create and no git commit, and ends asking which candidate to explore."
---

/architecture:improve deepening --medium terminal

Phase 1 already ran on this repository; do not scan it again. You may read the files the scan names below, and this skill's own files. The scan returned two candidates:

1. Quote path (confidence: strong). Files: parcels/quote_service.py, parcels/zones.py, parcels/rate_table.py. shallow-signal: QuoteService.quote, ZoneLookup.zone_for and RateTable.price each do one step and hand on to the next, and the fuel surcharge rule sits in two of them. runtime-claim: live bug, a 2 kg parcel to a zone B postcode is quoted 7.50 where the rate card gives 6.75, because the fuel surcharge is added in both QuoteService.quote and RateTable.price.
2. LabelPrinter (confidence: worth-exploring). Files: labels/label_printer.py. runtime-claim: dead code, nothing imports it.

[The level reader has already been run for this request and printed `verification: standard (docs/conventions/architecture.yaml verification at origin/main)`; use that line and do not run the reader again.]

Carry on from Phase 1.5 through Phase 2, and finish with the reply Phase 2 ends with.
