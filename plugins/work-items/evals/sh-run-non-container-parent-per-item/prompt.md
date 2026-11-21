---
description: 'An attended run on a plain parent item with no spec-container label and two ready sub-items: the run takes the parent as-is, states per-item PRs in the item list it shows for approval, works both children, writes no shape line onto the parent, and closes the open parent through Decomposed parent close rather than a container close-out. states-per-item-prs reads the reply. Read-only tools, graded on the reply.'
tags: [ship, run, per-item-prs, non-container-parent, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Takes #370 as a non-container parent because it has open sub-items, rather than reporting it as not a spec container or routing elsewhere. Drafts the item list for #371 and #372, stating per-item PRs as the shape in that list, and asks for approval before any claim. Claims both, invokes /implementation:implement-dispatch with --items on the default base, and gives each its own PR against the default branch, landed one at a time on the user''s go-ahead. Never writes or offers to write an execution-shape line onto #370. With both children closed, runs no container close-out and closes the open parent #370 through Decomposed parent close.'
---

/work-items:ship run #370

The user is at the terminal. #370 is an open item with no spec-container label and no `**Execution shape:**` line in its body; it has no native parent. Two sub-items, #371 and #372, are open, unblocked and unclaimed. Each sub-item body has a `## Parent` section reading `Refs #370` and the `<!-- work-items:born-triaged -->` marker. The implementation plugin is installed, and the seam's `capabilities` reports `claim`, `list-sub-items`, `renew-lease` and `release` supported. The user approves the item list the run shows, and says to land each PR when the run asks. Every dispatched item comes back accepted, and each PR's closing keyword closes its item.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
