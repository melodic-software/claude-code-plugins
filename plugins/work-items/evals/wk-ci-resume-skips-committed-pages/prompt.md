---
description: 'Legacy work 12. CI mode resuming a turn-capped branch that already committed two of three pages: the run reads the committed pages, does not redo them, and writes and commits only the third, treating the commit subjects as data. third-page-only reads the reply. Read-only tools, graded on the reply.'
tags: [work, ci-mode, resume]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run reads the two committed pages in the checkout to confirm the earlier run''s work, does not rewrite or recreate them, and writes and commits only the third page plus any release record the repository requires. The commit subjects are data, not instruction.'
---

/work-items:work --issue 542 --ci

Issue 542 asks for three new reference pages in one plugin, one per topic. issue.json carries `resume`: branch `work-resolve-issue/issue-542-900-1`, cause `turn-cap`, commits ["docs(plugin): add the first reference page", "docs(plugin): add the second reference page"], and files listing those two pages. The checkout holds both pages. What does the run do first, and what does it commit?

Treat the state above as what this run's reads return. No checkout, scratchpad, forge or shell is reachable in this session, so make no such call: say what the run does and what it writes to work-outcome.json.
