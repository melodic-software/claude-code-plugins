---
description: "Hard case. Why hard: The obvious fixes (a deny rule to remove, a wider Read grant, a copied directory) do not address it; the recorded finding is that the run refuses reads under the plugin's own directory, so only the hub text is measured. The V1 probe (paid-runs.md, 2026-10-02) showed a path-scoped `--allow-tools` Read grant does not lift it either."
tags: [run-validity, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says the run refuses reads under the plugin's own directory whatever the Read grant, so only the hub SKILL.md reaches the model, and says to move the content cases depend on into SKILL.md"
---

In my plugin eval, the with-plugin answers keep saying they couldn't open the skill's detailed reference, and the kept trace shows the Read of `skills/notes/reference/grading.md` failing with 'File is in a directory that is denied by your permission settings'. Read is in the case's allowed_tools. Why is this happening, and what should I change so the eval measures what the skill knows? Answer in under 150 words.
