---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 7. Written from plugins/knowledge/skills/absorb-upstream/SKILL.md \"Record location\" (record file name without --scope), \"Private sources stay private\" (a repository URL that does not read public is never read) and step 1 (the API read at the default branch head's pin). The sandbox's gh cannot read github.com/acme/agent-skills, so the source check reads unknown; id 7's written record and pin-marker expectations are unreachable. Graded: the reply names docs/upstream/acme-agent-skills.md (no scope suffix), no API call reads the source's tree or contents, and no record is written (shared by base and head). no-clone and names-local-checkout are head-side expectations (a URL that does not read public stops with the local-checkout form, where base clones it); a base failure is the old contract. Visibility: the scaffold runs git init with no remote, so docs/upstream reads local."
tags: [knowledge, absorb-upstream, outcome, scaffold, contract-change]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply names the record file docs/upstream/acme-agent-skills.md. No command clones the source and no API call reads its tree or contents, since its visibility does not read public. No record file is written under docs/upstream. On head the reply names the local-checkout form."
---

/knowledge:absorb-upstream https://github.com/acme/agent-skills
