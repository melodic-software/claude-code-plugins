---
description: "--fix on a README with one false claim. Fix gate and remediation, SKILL.md lines 318 and 344-348: present the Phase 3 findings, then suggest /implementation:implement followed by /verification:confirm, 'Do NOT auto-invoke either skill, the user drives both'; when those plugins are not installed, 'say so and stop'. Only this plugin loads in an eval run, so either form passes. Never re-inline a fix loop (line 348), so the scaffold's files stay untouched; the edit graders are path-scoped because the emit checklist (lines 170-173) may be written to a task-notes file. The claim sits in the documentation dimension, audited at every effort (lines 152-156). Needs --scaffold --allow-tools Write Edit."
tags: [codebase-health, audit, outcome, fix-gate, delegation]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "The reply reports the `npm run serve` claim as a finding citing README.md with a line number, then either suggests /implementation:implement followed by /verification:confirm or says the implementation and verification plugins are not installed. No Skill call to either skill, and no Edit or Write touches README.md, package.json, src/ or test/."
---

/codebase-health:audit README.md --docs-only --fix

Find what's wrong in the README and get it sorted.
