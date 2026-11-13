---
description: 'Legacy ship 2. Status on an integration-branch container shared by a cloud agent and a local machine, with one sibling claimed under a live lease: the shape and recorded branch, the shared-branch discipline, the one-item-in-flight deferral to the holder, no per-item PRs, no /work-items:work worktree path, and checkpoint vocabulary. names-integration-branch reads the reply. Read-only tools, graded on the reply.'
tags: [ship, status, shared-branch, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'States the shared-branch mode is in effect on integration/310-billing-migration and spells out its discipline: claim each item via the seam before working it even though work is sequential (the claim, not the branch, is the collision signal between the cloud and local sessions), renew the lease mid-flight on long items, pull before starting an item and push before closing it so every checkpoint is durable, no per-item PRs, one PR at the end carries the journey. Because a sibling sub-item is actively claimed, applies the one-item-in-flight rule: reports who holds the claim and defers new work instead of routing a second concurrent item onto the shared branch. Notes that this shape is worked on the shared branch directly or by run, not through /work-items:work''s default-branch worktree path. An item closed in this flow is a checkpoint.'
---

/work-items:ship #310

Item #310 is an open container item labeled spec-container. The container body carries `**Execution shape:** integration branch → single PR` and `**Integration branch:** integration/310-billing-migration`. A cloud agent and a local machine are both working this journey. Two sub-items remain open and unblocked; one other sub-item is currently claimed by the local machine with a live lease.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
