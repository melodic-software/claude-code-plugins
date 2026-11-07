---
description: 'Legacy decompose 6. A multi-session Brief and a user saying to just create everything: the container offer comes at the approval round defaulting to no, the execution-shape follow-up is recorded as a container body line, the container is created first with the Brief verbatim and the binding''s container label plus the human-gated label, items carry --parent, and the close-at-ship ritual is stated. shape-line reads the reply for the Execution shape line. Read-only tools, graded on the reply.'
tags: [decompose, spec-container, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Presents the breakdown first, since ''we already discussed it'' does not bypass the approval gate, with the container offer defaulting to no. After the operator approves the items and the container, asks one execution-shape follow-up and records per-item PRs as an **Execution shape:** line in the container body, not a repo setting. Creates the container first with the Brief verbatim as its body, labeled with the binding''s container label (spec-map) and needs-human, then publishes the slices blockers-first with --parent. States that the container closes at ship after a close-out review against its body.'
---

/work-items:decompose

The topic PLAN.md Brief covers three sessions of work. Publish the spec to the tracker so every session can read it; just create everything now, we already discussed it.

The topic is usage-billing. Its approved PLAN.md has a `## Brief` (TLDR, Problem, Goal, Constraints, Acceptance criteria, Captured assumptions, Out-of-scope, Deferred questions) and four phases. The binding is GitHub, a coordination provider, and its `config.container_label` is `spec-map`. The `decompose_container_publish` user config is unset.

When you present the breakdown, the operator answers: approve the items as drafted; yes, publish the spec container. To the execution-shape question the operator answers: per-item PRs.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
