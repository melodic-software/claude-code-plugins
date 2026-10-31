---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 1. Written from MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:29-38 (record directory and layer, resolved before the source), :59-60 (a clone goes in a new, empty directory outside the working tree) and :72-74 (pin). Covers lost sentences 11 and 12. The sandbox cannot clone github.com/acme/agent-skills or fetch the upstream-drift convention, so no record is written; id 1's record, pin marker, row and license expectations are unreachable. Graded: the reply names docs/upstream from the default layer, no clone lands inside the working tree, and no record is written (shared by base and head). names-local-checkout is a head-side expectation (clone-cli.js exit 1 names the local-checkout form); a base failure is the old contract. Visibility: the scaffold runs git init with no remote, so docs/upstream reads local and the unknown source (gh unreadable) proceeds to the clone instead of redirecting."
tags: [knowledge, absorb-upstream, outcome, scaffold, contract-change]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply reports the record directory docs/upstream from the default layer. Any clone runs into a new directory outside the working tree, never into the working directory. The clone cannot complete, so no record file is written under docs/upstream. On head the reply names the local-checkout form after the clone fails."
---

/knowledge:absorb-upstream https://github.com/acme/agent-skills --scope skills

The repository has three skills under skills/: plan-review, commit-guard and slide-maker. Its LICENSE file is MIT.
