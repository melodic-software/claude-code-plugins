---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 1. Written from plugins/knowledge/skills/absorb-upstream/SKILL.md \"Record location\" (record directory and layer, resolved before the source), \"Private sources stay private\" (a repository URL that does not read public is never read) and step 1 (the API read at the pin). The sandbox's gh cannot read github.com/acme/agent-skills, so the source check reads unknown and no record is written; id 1's record, pin marker, row and license expectations are unreachable. Graded: the reply names docs/upstream from the default layer, no API call reads the source's tree or contents, and no record is written (shared by base and head). no-clone and names-local-checkout are head-side expectations (a URL that does not read public stops with the local-checkout form, where base clones it); a base failure is the old contract. Visibility: the scaffold runs git init with no remote, so docs/upstream reads local."
tags: [knowledge, absorb-upstream, outcome, scaffold, contract-change]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply reports the record directory docs/upstream from the default layer. No command clones the source and no API call reads its tree or contents, since its visibility does not read public. No record file is written under docs/upstream. On head the reply names the local-checkout form."
---

/knowledge:absorb-upstream https://github.com/acme/agent-skills --scope skills

The repository has three skills under skills/: plan-review, commit-guard and slide-maker. Its LICENSE file is MIT.
