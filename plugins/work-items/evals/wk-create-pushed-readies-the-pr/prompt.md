---
description: 'Legacy work 8. With no merge hold and pr_open_state ready, the orchestrator opens the PR with create --pushed --worktree /work/wt-731, which runs ready itself, then dispatches one strong-tier PR owner for monitor and review, waiting event-driven. create-pushed-worktree reads the reply. Read-only tools, graded on the reply.'
tags: [work, pull-request, ready]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'It runs /source-control:pull-request create --pushed --worktree /work/wt-731 --unattended, which runs ready --unattended itself, so the orchestrator dispatches no ready. As soon as it returns, it dispatches one strong-tier PR owner into /work/wt-731 with the PR number to run the monitor watch and the post-green review, waits with run_in_background or Monitor, hands off to /source-control:babysit-prs, and never flips or merges the PR itself.'
---

/work-items:work

Run autonomously. The worker returned worktree /work/wt-731 on branch feat/731-csv-header, committed and pushed. The pre-PR diff gate passed, merge-hold.sh exited 1 for item #731 (no hold), and pr_open_state resolves to ready. What does the orchestrator do to open and ready the PR?

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
