---
description: "Hard: the release tagging rules are written out in exactly two files with drifted wording and no declared owner, and the user proposes a new shared file. Two other files mention tagging but only point at CONTRIBUTING.md, so a keyword count looks like four. Below the Rule of Three the contract refuses a new SSOT artifact and offers non-abstracting remedies: name one existing file the owner, have the other cite it, align wording. A model without the skill tends to accept the user's new-file idea. Written from the before SKILL.md contract (Decision framework bucket table, decision-framework.md Example 5)."
tags: [docs-hygiene, extract-ssot, outcome, scaffold, hard]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Agent, TodoWrite]
expected_outcome: "The reply declines to create docs/policies/release-tags.md or any other new file for the tagging rules because there are only two copies, recommends one of CONTRIBUTING.md or docs/releasing.md as the single owner, and shows the other file's section replaced by a pointer to the owner (by heading or link); aligning the wording is fine. No file is edited."
---

Our release tagging rules are written out twice, once in CONTRIBUTING.md and once in docs/releasing.md, and the two have started to word things differently. I want one source of truth for them. My idea is a new docs/policies/release-tags.md that both files link to. Can you give me the plan? Reply with it here, including the exact text you would put in each file. Don't change any files yet.
