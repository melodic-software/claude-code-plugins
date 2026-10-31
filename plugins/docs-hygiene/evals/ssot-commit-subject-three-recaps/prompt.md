---
description: "Hard: a commit-subject rule is recapped inline by three agent-facing files (an agent, a skill, an automation prompt) in drifted wording, while docs/conventions/commits.md already owns it under the H3 'Commit subject format'. The user does not name that file. Rule of Three is met, but the contract consolidates into the existing home rather than minting a new rule file, and migrates each call site to cite it by exact heading. A model without the skill tends to create a new rules file or point at the doc without its heading. Written from the before SKILL.md contract (Output type 'Concept already has an SSOT home', Citation form)."
tags: [docs-hygiene, extract-ssot, outcome, scaffold, hard]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Agent, TodoWrite]
expected_outcome: "The plan makes the existing docs/conventions/commits.md the one home, creates no new file, and replaces the recap in the committer agent, the ship skill and the nightly release prompt with a citation of commits.md by its exact heading \"Commit subject format\". No file is edited."
---

The commit subject rules are pasted into three of our agent files: the committer agent, the ship skill and the nightly release prompt. Every time the rule changes I have to update all three, and they already say it slightly differently. Clean this up so there is one place to change it. Reply with the plan and the exact replacement text for each file; don't edit anything yet.
