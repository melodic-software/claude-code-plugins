---
description: "The all sweep runs caches, build and git and never composes tree. Slash-invoked, so there is no Skill grader. clean SKILL.md line 130: 'Neither tree nor tree-batch is ever composed into all'; line 222: all is preflight once, then caches, build and git, and 'Does not run §6'; line 170: 'Never --apply on first invocation'. preflight-ran, build-dry-run-ran and git-prune-ran are with-only indicators of the three tiers. no-tree-reset fails any git-tree-reset run, dry-run included; no-raw-reset, no-apply and no-ack-prefix fail a reset, an apply or the guard acknowledgement. The file graders read a tracked edit and an untracked file (a tree reset removes both) and the build output and a cache (an apply removes them). The git tier's audits call gh, which the sandbox cannot reach; they report PRDataUnavailable and go on. Needs --scaffold --allow-tools Bash."
tags: [repo-hygiene, clean, outcome, all, destructive-gate, no-network]
max_turns: 40
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "preflight, the build (with caches) dry-run and git-prune dry-run run; git-tree-reset never runs; nothing is applied; the tracked edit, the scratch file, dist/bundle.js and the pytest cache all survive."
---

/repo-hygiene:clean all
