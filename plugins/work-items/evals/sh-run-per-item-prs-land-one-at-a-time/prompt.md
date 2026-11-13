---
description: 'Legacy ship 8. An attended run on a per-item-PRs container with four ready items, one claimed by another session: that item left out and reported, approval before claiming, implement-dispatch item-list mode on the default base, one PR per item, and PRs landed one at a time through /source-control:pull-request on the user''s go-ahead. excludes-held-354 reads the reply. Read-only tools, graded on the reply.'
tags: [ship, run, per-item-prs, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Leaves #354, claimed by the other session, out of the run and reports it. Drafts the item list for #351, #352 and #353 and asks for approval, then claims them and invokes /implementation:implement-dispatch with --items on the default base. Each accepted item gets its own PR against the default branch (opening a missing one with /source-control:pull-request create --pushed --worktree). Lands the PRs one at a time in dependency order: on the user''s go-ahead, ready brings each current with the default branch and merge lands it through /source-control:pull-request, whose gates apply; the next PR starts only after the previous one merged. The PR''s closing keyword closes the item. Never merges two PRs concurrently and never bypasses the pull-request skill''s gates.'
---

/work-items:ship run #350

The user is at the terminal. #350 is an open container item labeled spec-container. The container body carries `**Execution shape:** per-item PRs`. Four sub-items, #351, #352, #353 and #354, are open and unblocked; #354 is claimed by another session with a live lease. The implementation plugin is installed, and the seam's `capabilities` reports `claim`, `list-sub-items`, `renew-lease` and `release` supported. The user approves the item list the run shows, and says to land each PR when the run asks. Every dispatched item comes back accepted.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
