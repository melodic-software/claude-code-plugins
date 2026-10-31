---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 9 (absent at base: head-side expectation; a base failure is the old contract). Base has no visibility check and takes only a source URL (MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:8, :19-22, :106-108). Covers lost sentences 7 and 8 (a local checkout is a source) and 15 (the report names source and destination visibility). The source path is upstream-src/acme-internal-skills instead of ../acme-internal-skills, because a scaffolded sibling of the working directory may not reach the run. The prompt's unknown source reading is what the sandbox produces; its public reading for docs/upstream is not (repo-visibility.mjs prints unknown there, the same redirect row). Graded: the unknown source is handled as private, both reruns are named with absolute paths, and nothing is written. Visibility: the scaffold gives this repository a github.com remote and the checkout its own git init with a github.com remote; gh cannot read either."
tags: [knowledge, absorb-upstream, outcome, scaffold, stop-gate, contract-change]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A Bash call runs repo-visibility.mjs. The reply says the unknown source is handled as private, names a rerun with --out and an absolute path ending in docs/upstream, gives the source as an absolute path, and writes nothing. No Write call and no shell write under docs/."
---

/knowledge:absorb-upstream upstream-src/acme-internal-skills

That path is a local checkout of the private repository acme/internal-skills, and gh is not signed in. The visibility check prints {"visibility":"unknown","repo":"acme/internal-skills","reason":"gh could not read acme/internal-skills"} for it and {"visibility":"public"} for this repository's docs/upstream.
