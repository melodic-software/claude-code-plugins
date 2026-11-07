---
description: 'Legacy audit 5. CLAUDE.md has 260 visible lines and the repo''s own rule exempts it from the 200-line target because the repo runs a large rules layer: C1 still applies, but the overage is reported with the exemption under a REPO check-ID rather than as an unqualified FAIL. repo-check-id reads the reply. Bash is granted for the skill''s spine. Hard because the spine prints 260 against a 200 target, which invites a bare FAIL.'
tags: [audit, harness-memory, consumer-convention, hard]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply applies C1 against the 200-line target, reads the exemption in .claude/rules/instruction-budget.md and honors it instead of an unqualified FAIL, and reports the exemption under a REPO check-ID distinct from the doc-derived checks.'
---

/harness-memory:audit Audit this repo's CLAUDE.md. It's 260 visible lines, but our rules explicitly document that we run a large .claude/rules/ layer and deliberately exempt CLAUDE.md from the 200-line target. Leave user-level config out of this and don't change any files. No one is around to answer questions while this runs, so put what you find in your reply.
