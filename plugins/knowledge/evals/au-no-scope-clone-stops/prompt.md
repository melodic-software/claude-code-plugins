---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 7. Written from MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:46-48 (record file name without --scope), :59-60 (a clone goes in a new, empty directory outside the working tree) and :72-74 (pin of the default branch head). Covers lost sentences 11 and 12. The sandbox cannot clone github.com/acme/agent-skills or fetch the upstream-drift convention, so id 7's written record and pin-marker expectations are unreachable. Graded: the reply names docs/upstream/acme-agent-skills.md (no scope suffix), no clone lands inside the working tree, and no record is written (shared by base and head). names-local-checkout is a head-side expectation (clone-cli.js exit 1 names the local-checkout form); a base failure is the old contract. Visibility: the scaffold runs git init with no remote, so docs/upstream reads local and the unknown source (gh unreadable) proceeds to the clone instead of redirecting."
tags: [knowledge, absorb-upstream, outcome, scaffold, contract-change]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply names the record file docs/upstream/acme-agent-skills.md. Any clone runs into a new directory outside the working tree. The clone cannot complete, so no record file is written under docs/upstream. On head the reply names the local-checkout form after the clone fails."
---

/knowledge:absorb-upstream https://github.com/acme/agent-skills
