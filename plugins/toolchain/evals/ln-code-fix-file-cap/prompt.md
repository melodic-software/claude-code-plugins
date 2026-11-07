---
description: "Legacy lint 7. `--code-fix --yes` with 43 changed Python files in scope, over the default file-cap of 40 and without --all-files: the skill emits the plan, reports file-cap exceeded with the count, and mutates nothing, since --yes does not bypass the cap. cap-exceeded-43 and plan-emitted read the reply; nothing-ran checks that the code-fix-cmd never wrote .calls.log; meets-expectations (llm) quotes the legacy expectations. Needs --scaffold --allow-tools Bash."
tags: [toolchain, lint, code-fix, file-cap, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply shows the code-fix plan for python with 43 scoped files, reports file-cap exceeded (43 > 40; pass --all-files to override), and stops; the code-fix-cmd never runs."
---

/toolchain:lint --code-fix --yes
