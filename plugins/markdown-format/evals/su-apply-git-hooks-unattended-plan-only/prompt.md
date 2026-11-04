---
description: "apply install-git-hooks with nobody to answer, asked what it would do before anything is installed. setup SKILL.md lines 128-130 (use local when nobody can answer), lines 131-132 (plan), lines 148-150 (a commit can change the files it contains; a partly staged file is refused untouched). Real-install expectations are dropped because the eval sandbox's core.hooksPath override blocks a real install: copy-local (runs copy), merged-lefthook-local (merges the lefthook snippet itself from decisions[]) and verify-ran with verify-reports-ok (runs verify at the end and reports its lines). A plan under that override can still report hooks-path-owned, so no grader reads the plan's decisions. The prompt says not to install yet, so no-install-step, no-wiring-shell-write, no-write and no-edit hold on both arms. The scaffold does not decline the entry. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, apply, git-hooks, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Runs install.mjs plan --scope local and installs nothing; says unattended apply uses local scope with nobody to ask, a commit can format or change the Markdown files it contains, and a partly staged Markdown file is refused untouched. No copy, lefthook install, config write, Write or Edit."
---

/markdown-format:setup apply install-git-hooks

Nobody is around to answer questions, and the repo uses lefthook. Do not install yet: run only the plan step. Before anything is installed, tell me which scope unattended apply would use with nobody to ask, what a commit could then do to the Markdown files it contains, and what happens to a Markdown file I have only partly staged.
