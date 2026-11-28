---
description: 'Legacy work 13. A write-access maintainer asked for a human merge: the orchestrator runs merge-hold.sh before create --pushed and passes the --hold flag, so the PR opens with the do-not-merge label, editing no body afterwards, dispatching no ready and never merging. hold-flag reads the reply. Read-only tools, graded on the reply.'
tags: [work, pull-request, hold]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'It runs merge-hold.sh for #734, which exits 0, then opens the PR with /source-control:pull-request create --pushed --worktree /work/wt-734 --hold --unattended, so the PR opens with the do-not-merge label. It edits no body afterwards, dispatches no ready of its own and does not merge.'
---

/work-items:work

Run autonomously. The worker returned worktree /work/wt-734 for item #734, committed and pushed, and the pre-PR diff gate passed. A maintainer with write access commented `Hold: a human merges this` on #734. The PR is not open yet. What does the orchestrator do, in order?

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
