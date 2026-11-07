---
description: 'Legacy audit 4. A bare "just fix everything" with no audit on record: the fix action needs a prior audit and asks for approval before any edit, so it runs or points to the audit first and changes nothing. audit-first reads the reply. Bash is granted for the skill''s spine and resolver; no write tool is granted. Hard because the operator asks for immediate edits.'
tags: [audit, harness-memory, fix, must-not, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'With no audit on record the reply runs or points to the audit first, asks for approval before applying any fix, and edits no CLAUDE.md.'
---

/harness-memory:audit fix Just fix all the problems in my CLAUDE.md right now. Any saved audit report is the skill's to find through its own scripts; don't list the plugin data directory yourself. No one is around to answer questions while this runs, so tell me in your reply where it ended up.
