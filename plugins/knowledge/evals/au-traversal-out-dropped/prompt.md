---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 3. Written from MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:25 and :40-44 and MB:plugins/knowledge/reference/config.md:32 (an --out value with a .. segment is invalid: name it, drop the argument layer, fall back). Covers lost sentences 3 and 9 through the part base and head share: head widened --out to an absolute private directory, but a .. segment stays invalid in both. The record directory is resolved before the source is read, so the graded step precedes the clone the sandbox cannot run; id 3's 'writes the record under docs/upstream' is unreachable and is graded as the reported default directory instead. Visibility: the scaffold runs git init with no remote, so docs/upstream reads local and the run is not redirected."
tags: [knowledge, absorb-upstream, outcome, scaffold, path-safety, config-layer]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply names --out ../elsewhere as invalid (its .. segment) and reports the default directory docs/upstream. No Write call and no shell write targets elsewhere."
---

/knowledge:absorb-upstream https://github.com/acme/agent-skills --out ../elsewhere

docs/conventions/knowledge.yaml does not exist.
