---
description: "Legacy check eval 1, skill-present branch. /skill-quality:check check my-skill over a scaffolded skill whose SKILL.md links a reference file it does not ship. check SKILL.md Action: check: run check-skill.sh, report PASS/FAIL from its exit code, FAIL: lines verbatim, WARN: lines grouped after as advisory. ran-gate (indicator) grades that the gate script ran; fail-line-verbatim grades the broken-ref FAIL line quoted as printed, either whole or with its message verbatim under a FAIL heading (the shape all three smoke 2 replies took); reports-fail-verdict grades a FAIL verdict for my-skill; warns-after-fails grades the advisory WARN lines (Gotchas, disable-model-invocation) reported after the FAIL line; no-edit and no-write grade that nothing is fixed unasked. The markdownlint line varies with the host, so no grader reads it. The prompt says where my-skill lives because in an eval run the checker's default root (CLAUDE_PROJECT_DIR or the git toplevel) is the sandbox home, not the workspace: smoke 1's plain run printed 'Skill not found' for <sandbox>/home/.claude/skills/my-skill. Needs --scaffold --allow-tools Bash."
tags: [skill-quality, check, outcome, scaffold, no-network]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep]
expected_outcome: "The reply runs the static gate on my-skill, reports it as FAIL, quotes 'FAIL: broken skill-internal ref: reference/style-guide.md ...' as the checker printed it, lists the WARN lines after it as advisory, and edits nothing."
---

/skill-quality:check check my-skill

my-skill is at .claude/skills/my-skill under the current working directory.
