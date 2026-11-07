---
description: 'Legacy ship 7. An attended run on an integration-branch container with three independent ready items and a fourth blocked by one of them: approval of the drafted item list before any claim, implement-dispatch item-list mode with --base on the integration branch, one-at-a-time landing as checkpoints, no per-item PRs, the unblocked item through a second approval, and a draft integration PR that is not merged. dispatch-base-integration reads the reply. Read-only tools, graded on the reply.'
tags: [ship, run, shared-branch, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Resolves the container and shape, gates the seam''s claim verbs, finds no claim held by another session, drafts an item list (id, title, spec as data, targets, acceptance) for the three ready items and asks the user to approve it before claiming. After approval it claims the three, invokes /implementation:implement-dispatch with --items and --base pointing at the remote integration branch, and lands accepted branches one at a time onto the integration branch in a worktree (pull, merge, build and test gate, push), closing each item as a checkpoint before the next merge. A conflict is resolved the way /source-control:pull-request ready resolves its base merge, both sides'' intent first. No per-item PRs. After the blocker closes, the fourth item joins a next round through the same approval. When all sub-items are closed it opens the single integration PR as a draft and does not merge it.'
---

/work-items:ship run #340

The user is at the terminal. #340 is an open container item labeled work-map. The container body carries `**Execution shape:** integration branch → single PR` and `**Integration branch:** integration/340-search-rewrite`. No sub-item is claimed. Three sub-items are open and unblocked with no edges between them; a fourth is blocked by one of the three. The implementation plugin is installed, and the seam's `capabilities` reports `claim`, `list-sub-items`, `renew-lease` and `release` supported. The user approves each item list the run shows. Every dispatched item comes back accepted, the fourth included once its blocker closes.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
