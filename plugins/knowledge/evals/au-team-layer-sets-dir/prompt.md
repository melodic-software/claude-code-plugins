---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 2. Written from MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:33-37 and MB:plugins/knowledge/reference/config.md:18-20 (the team layer applies when the root is inside a git working tree and is neither $HOME nor an ancestor of it). Covers lost sentences 2 and 10 through the outcome base and head share: with the working directory as its own git top-level, the team key sets the record directory. Base finds that root through CLAUDE_PROJECT_DIR or git rev-parse, head through work-root.mjs; the mechanism is not graded, since no outcome tells them apart here. The sandbox cannot clone github.com/acme/agent-skills, so id 2's 'writes the record at docs/provenance/acme-agent-skills.md' is unreachable; graded: the reply reports docs/provenance from the team layer, and nothing is written under docs/upstream. Visibility: the scaffold runs git init with no remote and commits docs/conventions/knowledge.yaml, so the record directory reads local and the run is not redirected."
tags: [knowledge, absorb-upstream, outcome, scaffold, config-layer]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply reports the record directory docs/provenance and names the team layer or docs/conventions/knowledge.yaml as its source, without calling the team layer skipped. No Write call and no shell write targets docs/upstream."
---

/knowledge:absorb-upstream https://github.com/acme/agent-skills

docs/conventions/knowledge.yaml contains the line `upstream_records_dir: docs/provenance`. No --out was passed.
