---
description: "Legacy script-the-deterministic-work 5. The scaffold seeds .github/pull_request_template.md (four distinctive headings, a checklist) and notes/branch.md; the prompt adds where the branch summary is. reads-template (trace: a Read, Grep or Bash naming the template) and frame-from-template (trace: one assistant record holding all four headings, or one shell command that copies the template: cp to a .md path, cat with a stdout redirect to a file other than /dev/null, or cat piped to tee of a .md path; a plain read, a stderr redirect or a second .md argument to cat does not count) are regex; frame-from-template checks that the template's frame is present, not whether it was typed or copied, which judgment-slots-only (llm, trace) decides as it quotes legacy expectations 1-3; notes/branch.md gives no risk or test-run facts, so the Risk and rollback and Test evidence slot contents are not graded. Needs --scaffold --allow-tools Bash Write Edit."
tags: [discipline, script-the-deterministic-work, outcome, scaffold, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "Takes the frame from the repo's pull request template rather than typing it, and writes only the judgment slots, taking what changed and why from notes/branch.md."
---

/discipline:script-the-deterministic-work draft the PR body for this branch; you were about to type the whole thing out section by section. (The branch's changes are summarized in notes/branch.md.)
