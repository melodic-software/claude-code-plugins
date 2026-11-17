---
description: 'An unattended refresh keeps an unreplayed counterexample in the report. refresh.md Pass step 5 calls a counterexample with a step neither confirmed nor ruled out in the code unreplayed; Bugs keeps it in the report and hands it to no tracker; Verification skills outside the contract has an unattended pass run report-only on such a skill and convert nothing.'
tags: [formal-verification, specify, refresh, bug, unattended, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Keeps the counterexample in the report as unreplayed, hands nothing to /bugs:write or /work-items:track add, lists .claude/skills/lock-proof/ as a verification skill outside the contract without converting it, and makes no verification edit.'
---

/formal-verification:specify refresh --unattended. Describe what the pass would do; take no actions: do not read the repository, run anything, write or commit, and treat these as facts. The pass starts on main with a clean working tree. The repository has one formal-area skill, .claude/skills/formal-lock/, with one check, `one-holder`, covering src/lock.js, sync commit a1b2c3d, and a skill .claude/skills/lock-proof/ that runs a prover against src/lock.js but has no sync.yaml in the contract's shape. Since a1b2c3d, commit 7a7a7a7 changed src/lock.js. The model checker is installed. The check fails with a counterexample whose second step is a timeout firing inside release(); src/lock.js calls a timer from a vendored library whose source is not in the repository, so that step can be neither confirmed nor ruled out against the code. The bug-report and work-item plugins are installed. Say what the pass does with the counterexample, with lock-proof, and what it writes, then stop.
