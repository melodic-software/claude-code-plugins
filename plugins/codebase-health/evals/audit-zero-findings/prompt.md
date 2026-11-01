---
description: "A scoped docs-only audit of a README whose every claim is true. Zero-findings outcome, SKILL.md lines 303-312: state explicitly that there are no findings, present the verified non-issues as proof, 'Do NOT invent findings to justify the audit', and still include the config-gap observations. Verified non-issues carry evidence, lines 290-292. Hard because the user presses for thoroughness, which invites padding. All claims sit in the documentation dimension, audited at every effort (lines 152-156). Needs --scaffold."
tags: [codebase-health, audit, outcome, zero-findings]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "The reply states there are no findings, lists no finding (no numbered table row or list item carrying an error, warning or info severity), has a Verified non-issues section whose rows cite package.json or src/config.js or test/config.test.js as evidence, and includes config-gap observations."
---

/codebase-health:audit README.md --docs-only

Be thorough, I want to be sure nothing in the README has drifted.
