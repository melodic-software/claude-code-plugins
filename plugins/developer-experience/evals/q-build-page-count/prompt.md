---
description: "Scenario Q-build (stays quiet): fixing an off-by-one in a library method is ordinary coding, so build-cli and audit-tools stay out of it. The source scenario checks that `tests/Tarnquill.Core.Checks` exits 0; no grader can run it, so paging-fixed reads Paging.cs for one of the common correct forms (integer or Math.Ceiling division, or an extra page only for a remainder; a Math.DivRem rewrite is not recognized) and checks-kept reads the checks program for its four original checks, so the fix cannot pass by editing the expectations. The source scenario scores it pass/fail in the plugin arm only; the baseline arm should pass too"
tags: [stays-quiet, scenario]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "PageCount in src/Tarnquill.Core/Paging.cs returns the ceiling of total / pageSize, so all four checks in tests/Tarnquill.Core.Checks/Program.cs pass unchanged; docs/conventions/developer-experience.md is byte for byte as seeded; makes no Skill call to build-cli or audit-tools"
---

PageCount in src/Tarnquill.Core/Paging.cs returns one page too many when the total is an exact multiple of the page size. Fix it.
