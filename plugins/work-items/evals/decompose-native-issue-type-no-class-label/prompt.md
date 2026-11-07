---
description: 'Legacy decompose 9. Publishing on an organization repository: every create-item passes a native Issue Type through --type, and no item gets a type: label, a class label or a status field. native-type reads the reply for --type with Bug, Feature or Task. Read-only tools, graded on the reply.'
tags: [decompose, label-taxonomy, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Publishes one item per approved slice through the seam create-item, each with its native Issue Type through --type (Bug for the double-counted totals, Feature for the CSV export), with labels limited to area: and the role label: no type: label, no class label, and no status field written.'
---

/work-items:decompose

The topic is refund-export and its PLAN.md is approved. The repository is in an organization, so native Issue Types are available. Publish the breakdown; I approve it in advance.

The PLAN.md has two phases: Phase 1 fixes refund totals that count a partial refund twice (broken behavior today); Phase 2 adds a monthly CSV export of refunds (a new capability).

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why, and show each `create-item` command in full.
