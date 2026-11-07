---
description: 'Legacy ship 11. A per-item-PRs run where create --pushed opened PR 906 for #362 and ready --unattended refused because #362 is already closed: PR 906 stays a draft, the report row carries the superseded reason, the item is not reopened, the PR is not flipped another way, and it is not merged. pr-906-stays-draft reads the reply. Read-only tools, graded on the reply.'
tags: [ship, run, per-item-prs, pull-request, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'PR 906 stays a draft. The run carries the refusal reason create --pushed reported (item #362 already closed, so the PR is superseded) into its report row for #362, does not reopen the item or flip the PR another way, and does not merge it.'
---

/work-items:ship run #360

Item #360 is an open container item labeled work-map. The container body carries `**Execution shape:** per-item PRs`. create --pushed opened PR 906 for item #362 and ran /source-control:pull-request ready --unattended on it, which refused: item #362, the issue the PR closes, is already closed, so the PR is superseded.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
