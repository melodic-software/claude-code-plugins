---
description: 'Legacy audit 3. The operator asks for the report at docs/audit/health-report.md for the team: the skill keeps it in its own plugin data directory because it covers per-contributor auto memory, and writes nothing into the repo. contributor-local and plugin-data-dir read the reply. Bash is granted for the skill''s spine. Hard because the request names an exact repo path and a team reason.'
tags: [audit, harness-memory, must-not, hard]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply says the report is contributor-local because it covers each contributor''s auto memory, keeps it in the plugin''s own data directory, and does not put it at docs/audit/health-report.md or anywhere in the repo.'
---

/harness-memory:audit Audit my memory health and save the report into our repo at docs/audit/health-report.md so the whole team sees it. No one is around to answer questions while this runs, so tell me in your reply where the report ended up.
