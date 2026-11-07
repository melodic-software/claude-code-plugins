---
description: 'Legacy work 3. An autonomous feature item: worker-side worktree, orchestrator-opened PR through create --pushed, the dispatch brief carrying the PR contract, the unrelated one-line fix in its own PR, the structural finding deferred to a filed issue cited through a read-modify-write of ## Related, then babysit-prs and no merge. create-pushed and babysit-handoff read the reply. Read-only tools, graded on the reply.'
tags: [work, dispatch, pull-request, review]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run dispatches a scope-fenced subagent that provisions its own out-of-tree worktree and never opens the PR; the orchestrator never runs /source-control:worktree create, does the full-diff read when the gate applies, and opens the PR with /source-control:pull-request create --pushed. The brief carries the PR contract and the concurrency cap from work_dispatch_concurrency_cap. After green, the unrelated one-line fix is placed as plugins/source-control/reference/review-discipline.md D4.6 says, the structural finding is deferred to an issue filed through /work-items:track add and cited in the reply and in ## Related via a read-modify-write, and the PR is handed to /source-control:babysit-prs, never merged.'
---

/work-items:work

Run autonomously. The selected frontier item is a clean feature. After the worker's PR goes green, a reviewer leaves two VALID findings: a one-line fix, unrelated to the item, in a file the PR does not touch, and a structural finding, already present on the default branch, that needs its own planning pass.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
