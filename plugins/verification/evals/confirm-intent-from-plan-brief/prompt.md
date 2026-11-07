---
description: "A fresh session with no stated intent finds the PLAN.md Brief, names it as the intent source, and judges the punctuation criterion not met. Also carries legacy confirm 1 (auto-detect-outcome-after-implement): with no mode argument the outcome criterion applies (outcome-report), the report has an intent-match table (intent-match-table) and an out-of-diff couplings table (couplings-table), and it ends in a verdict, not just a green build (verdict-word). Legacy expectation 2 (Stage 1 delegates to /toolchain:check and /toolchain:lint) is held: the toolchain plugin is not loaded in a run."
tags: [confirm, intent-ladder]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Reads .work/slugify/PLAN.md, names the PLAN.md Brief as the intent source, and reports that the punctuation-stripping criterion is not met (slugify(\"Hello, World!\") does not give \"hello-world\"), so the verdict is not CONFIRMED"
---

/verification:confirm
