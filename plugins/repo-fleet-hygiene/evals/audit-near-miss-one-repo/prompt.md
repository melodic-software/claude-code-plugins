---
description: "Near miss that must not route. Cleanup inside one checkout belongs to repo-hygiene and source-control, which own per-repository cleanup (SKILL.md lines 18-21: this skill owns cross-repository discovery and rollup, not per-repository cleanup decisions); the description (line 2) is for a fleet. The request names one repository and its caches, so /repo-fleet-hygiene:audit must stay quiet. plugin eval loads only this plugin, so the check is quietness, not a competitor win. Tagged regression-guard: the without-plugin arm cannot call this skill and passes by construction; the paired hard case is sync-apply-needs-consent. Read-only tools. Needs --scaffold."
tags: [repo-fleet-hygiene, audit, outcome, routing, near-miss, regression-guard]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "No Skill call to repo-fleet-hygiene:audit."
---

In this repo, which local branches are already merged into main? Also clear out node_modules and the build folder. It's just this one checkout.
