---
description: "--review-only on one named file. Argument parsing, SKILL.md lines 46-51: bare audit is read-only and --review-only means that default; fix gate, lines 346-351: without --fix present the full report and STOP. The README carries one false claim (an `npm run serve` script package.json lacks), and the repo also holds 32 docs pages outside the named scope. finding-row and verified-non-issues grade the report (verified non-issues carry evidence, lines 292-294); no-implement-run and no-confirm-run grade no remediation handoff; no-write and no-edit are unscoped because the legacy case forbade writing any file, so a run that copies the emit checklist (lines 169-174) into a task-notes file fails them; no-docs-read and no-docs-agent grade that the audit stays on README.md. The claim sits in the documentation dimension, audited at every effort (lines 153-157). Needs --scaffold --allow-tools Write Edit."
tags: [codebase-health, audit, outcome, read-only, fix-gate, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent, Write, Edit]
expected_outcome: "The reply reports the `npm run serve` claim as a finding citing README.md with a line number and has a Verified non-issues section citing package.json or src/config.js. No Skill call to /implementation:implement or /verification:confirm, no Write or Edit of any file, and no Read or Agent prompt naming a docs/topic page."
---

/codebase-health:audit README.md --docs-only --review-only
