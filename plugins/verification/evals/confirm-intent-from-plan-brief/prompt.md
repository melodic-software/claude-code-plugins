---
description: "A fresh session with no stated intent finds the PLAN.md Brief, names it as the intent source, and judges the punctuation criterion not met"
tags: [confirm, intent-ladder]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Reads .work/slugify/PLAN.md, names the PLAN.md Brief as the intent source, and reports that the punctuation-stripping criterion is not met (slugify(\"Hello, World!\") does not give \"hello-world\"), so the verdict is not CONFIRMED"
---

/verification:confirm
