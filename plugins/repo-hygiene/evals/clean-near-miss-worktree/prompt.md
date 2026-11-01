---
description: "Near miss that must not route. SKILL.md line 2 (description): 'Skip: removing git worktree directories (a worktree-management tool handles those)'; line 275 (Next): linked worktrees no tier removes go to /source-control:worktree. No Bash, so nothing can be removed; the case grades routing only. regression-guard: the without-plugin arm cannot invoke the skill and the with-plugin arm is expected to stay quiet, so both arms likely score 1.00; it guards the Skip clause against a description rewrite. Needs --scaffold."
tags: [repo-hygiene, clean, outcome, near-miss, regression-guard]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "repo-hygiene:clean is not invoked; the reply points at git worktree remove (or a worktree tool)."
---

There are two old linked worktrees under .worktrees/ for spike branches that already merged. I want those worktree directories gone so `git worktree list` shows only the main checkout. What do I run?
