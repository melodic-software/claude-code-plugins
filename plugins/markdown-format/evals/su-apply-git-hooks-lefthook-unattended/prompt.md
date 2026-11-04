---
description: "apply install-git-hooks with nobody to answer, in a lefthook repository. setup SKILL.md line 130 (local when nobody can answer), lines 131-146 (plan, copy, decisions, verify), reference/git-hook-decisions.md (the agent merges the lefthook-config snippet, appends the exclude line and runs lefthook install), lines 148-150 (the entry rewrites and re-stages; a partly staged file is refused untouched). The merge is an llm trace grader, not file_exists: the exclude decision hides lefthook-local.yml from git, and which files file_exists counts is UNVERIFIED for an excluded path. verify prints missing until the job is wired and lefthook install has run, so verify-reports-ok separates a complete run. Host-bound on lefthook. The installer rejects --scope=local. The scaffold does not decline the entry. Needs --scaffold --allow-tools Bash Write Edit."
tags: [markdown-format, setup, apply, git-hooks, no-network]
max_turns: 24
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Uses local scope without asking; runs install.mjs plan and copy, merges the lefthook snippet into lefthook-local.yml itself from decisions[], runs lefthook install and verify, and reports verify's ok line; says a commit can change the Markdown it contains and a partly staged Markdown file is refused untouched. No dependency install, lint run or shared-scope write."
---

/markdown-format:setup apply install-git-hooks

Nobody is around to answer questions. The repo uses lefthook. When you finish, tell me what verify printed, what a commit can now do to the Markdown files it contains, and what happens to a Markdown file I have only partly staged.
