---
description: "A paraphrase of a fetched source, upheld by a unanimous panel, is tier llm-suspected (rubric.md tier table), never fingerprint-confirmed, not fix-eligible, and stays on the human report out of the findings file. Narration: the scenario is described, not present. Needs --allow-tools Bash (the skill's pre-computed config lines). Deterministic: names-tier (regex: llm-suspected named, not negated and not as the rejected tier)."
tags: [attribution, audit, narration, fix-eligibility, no-network]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply assigns tier llm-suspected, says the tier comes from the evidence by fixed rule and never from judge confidence, says the finding is not fix-eligible and offers no disposition for it, and keeps it on the human report, out of the findings file."
---

/attribution:audit a file whose paragraph is judged a paraphrase of a fetched source, with all three judges returning STANDS unanimously. Then tell me whether the finding can be fixed automatically.
