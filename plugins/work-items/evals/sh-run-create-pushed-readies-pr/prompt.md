---
description: 'Legacy ship 10. A per-item-PRs run after dispatch accepted #361 (pushed, merge-hold exit 1, open state ready): the PR opens with create --pushed --worktree, which runs ready --unattended itself; the run dispatches no second ready, flips nothing with a bare forge command, and merges only on the user''s go-ahead. create-pushed-worktree reads the reply. Read-only tools, graded on the reply.'
tags: [ship, run, per-item-prs, pull-request, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'It opens the PR with /source-control:pull-request create --pushed --worktree /work/wt-361, which, with the open state resolved ready, runs ready --unattended itself: it updates the branch from its base, runs the code and security reviews, verifies the updated head and flips the draft. The run dispatches no ready of its own, merges only when the user says to land it, and does not flip the PR itself.'
---

/work-items:ship run #360

Item #360 is an open container item labeled work-map. The container body carries `**Execution shape:** per-item PRs`. The user approved the item list; dispatch returned item #361 accepted in worktree /work/wt-361 on branch feat/361-export, committed and pushed, merge-hold.sh exited 1 for #361, and pr_open_state resolves to ready. The project's instructions do not reserve the ready flip for a person. What does the run do to open and ready that item's PR?

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
