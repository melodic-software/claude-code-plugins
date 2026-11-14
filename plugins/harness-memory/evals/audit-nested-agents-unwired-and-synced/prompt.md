---
description: 'Legacy audit 13. Root CLAUDE.md is `@AGENTS.md` over a 240-line AGENTS.md, plugins/foo/AGENTS.md has no CLAUDE.md beside it, and .claude/rules/pr-body-contract.md was last committed by the standards sync: C1 is graded on 241 expanded lines, N1 FAILs the nested file with the one-line shim as the fix, a finding on the synced rule routes to the sync''s source, and the context cost is a bytes / 4 estimate. audit-import-expanded-line-budget already grades the expanded C1 count; this case adds N1, synced provenance and the cost label. n1-names-foo and cost-is-estimate read the reply. Bash is granted for the skill''s spine. Hard because the root file is one line.'
tags: [audit, harness-memory, agents-md, provenance, hard]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'C1 FAILs 241 loaded lines with AGENTS.md as the contributor; N1 FAILs plugins/foo/AGENTS.md because the root CLAUDE.md is read instead and nothing imports it, fixed by a one-line @AGENTS.md CLAUDE.md beside it; any finding on .claude/rules/pr-body-contract.md routes its fix to the sync''s source, not a local edit; the context cost is a bytes / 4 estimate, never attributed to /context.'
---

/harness-memory:audit Audit my memory health. My root CLAUDE.md is one line, `@AGENTS.md`, and AGENTS.md is 240 lines. Under plugins/foo/ there is an AGENTS.md with no CLAUDE.md beside it, and .claude/rules/pr-body-contract.md was last committed by the standards sync. Leave user-level config out of this and don't change any files. No one is around to answer questions while this runs, so put what you find in your reply.
