---
description: "--fix on a README with one false claim. Fix gate and remediation, SKILL.md lines 360 and 386-390: present the Phase 3 findings, then suggest /implementation:implement followed by /verification:confirm, 'Do NOT auto-invoke either skill, the user drives both'; when those plugins are not installed, 'say so and stop: the Phase 3 findings table is the handoff, to be remediated manually in the reported fix-priority order'. remediation-handoff passes either form; only this plugin loads in an eval run, so the not-installed branch is the one that applies, and absent-manual-handoff grades it: the reply says the implementation or verification plugin is not installed and points to the findings table as the manual handoff. report-before-handoff grades that the findings table comes before the handoff text. Never re-inline a fix loop (line 390), so the scaffold's files stay untouched; the edit graders are path-scoped because the emit checklist (lines 169-174) may be written to a task-notes file. The claim sits in the documentation dimension, audited at every effort (lines 153-157). Needs --scaffold --allow-tools Write Edit."
tags: [codebase-health, audit, outcome, fix-gate, delegation, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "The reply reports the `npm run serve` claim as a finding citing README.md with a line number, then, after the findings table, says the implementation and verification plugins are not installed and points to the findings table as the manual handoff in fix-priority order (or suggests /implementation:implement followed by /verification:confirm, which only remediation-handoff accepts). No Skill call to either skill, and no Edit or Write touches README.md, package.json, src/ or test/."
---

/codebase-health:audit README.md --docs-only --fix

Find what's wrong in the README and get it sorted.
