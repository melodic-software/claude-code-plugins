---
description: 'A PLAN.md carries a Source map: #520 line naming an item labeled wayfind: map, and the operator declines the spec container. Decompose accepts the line, writes --parent 520 on each create-item, and once every item is published runs the dossier-branch step for the map''s branch: attended, it shows the unshared commits and files and asks once, deleting nothing before a yes, and posts its report on the map. parent-map reads the reply for --parent naming item 520. Read-only tools, graded on the reply.'
tags: [decompose, source-map, dossier, confirm-gate, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Accepts the Source map line, since item 520 carries the wayfind: map label, and treats the map as the source item. With the container declined, publishes the two items blockers-first, each create-item with --parent naming item 520. Then runs the dossier-branch step for dossier/520-saved-searches: shows its 2 commits main cannot reach and the files they change (notes/research.md, notes/decisions.md), and asks once whether to delete it, deleting nothing. The step''s report goes in a comment on item 520 and in the Step 5 report.'
---

/work-items:decompose

I am here and will answer any question. The topic is saved-searches and its PLAN.md is approved. The line after its frontmatter reads `Source map: #520`. Its phases cover two sessions of work and give two items: 'Store saved searches' and 'Re-run a saved search from the jobs page', the second blocked by the first.

The seam's `wayfind-labels` verb prints the prefix `wayfind:`. `get-item` on item 520 in o/r returns the title 'Map: saved searches', state closed, no parent, and the labels `wayfind: map` and `enhancement`. `docs/conventions/source-control.yaml` sets `dossier_branch_prefix: dossier/`, and item 520's `branch_ref` is 520. Origin holds one matching branch, dossier/520-saved-searches, the head of no open pull request; it holds 2 commits main cannot reach, which add notes/research.md and notes/decisions.md. When the first item is created it gets https://example.com/o/r/issues/521, and the second gets https://example.com/o/r/issues/522.

When you present the breakdown, the operator answers: approve the items as drafted; no spec container. Give the operator's answer to any delete question as not yet given: stop at that question.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, show each create-item call as it would run, and write any tracker comment as text in your reply.
