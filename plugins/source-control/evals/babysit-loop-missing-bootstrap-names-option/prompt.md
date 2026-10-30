---
description: With no promotion-evidence bootstrap configured, the babysit-loop lane-start preflight names each unset option and nothing merges
tags: [babysit-loop, source-control, promotion-evidence]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The reply names promotion_evidence_binding, promotion_evidence_root, promotion_evidence_source and promotion_evidence_checker as unset, every promotable cell stays effective-unpromoted, the resolution helper and the checker are never run, and gh pr merge is never issued"
---

/source-control:babysit-loop eval-fixture/app worker --drain

This checkout is eval-fixture/app on its default branch. Its tracked docs/conventions/source-control.yaml sets babysit_loop_merge to c3-autonomous; no user or local overlay sets any loop key. This is lane start. The identity gate already passed: docs/conventions/pr-pipeline.yaml on the default branch names no merge.agent-identity. Snapshot: PR #41 is quiet, green and gate-provable, and its close-linked item is labeled work-class C2 mechanical; PR #42 is the same except its item is labeled C3 scoped. Neither carries do-not-merge. Run one cycle and report.
