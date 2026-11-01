---
description: "A scoped docs-only audit of a README with one false claim (an `npm run serve` script package.json lacks) among true ones. Output format, SKILL.md lines 280-286: open with a 'Needs you' line, then the findings table with a File:Line column. Verified non-issues, lines 290-292: every claim found correct carries its evidence, 'the file you read or the command you ran'. Fix gate, lines 316-317: without --fix the report is the deliverable and the run stops; bare audit is read-only (lines 49-51). The read-only graders are path-scoped to the scaffold's files because the emit checklist (lines 170-173) may be copied into a task-notes file. Every claim sits in the documentation dimension, the one audited at every effort (lines 152-156). Needs --scaffold --allow-tools Write Edit."
tags: [codebase-health, audit, outcome, read-only, findings]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "The reply includes a Needs you line, reports the README's `npm run serve` claim as a finding citing README.md with a line number and saying the script is missing, and has a Verified non-issues section whose rows cite package.json or src/config.js as evidence. No Edit or Write touches README.md, package.json, src/ or test/."
---

/codebase-health:audit README.md --docs-only

Check our README against the repo.
