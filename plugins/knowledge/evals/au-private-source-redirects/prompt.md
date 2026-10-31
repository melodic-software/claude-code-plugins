---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 8 (absent at base: head-side expectation; a base failure is the old contract). Base has no visibility check and takes only a source URL (MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:8, :19-22, :106-108). Covers lost sentences 7 and 8 (a local checkout is a source) and 15 (the report names source and destination visibility). The source path is upstream-src/acme-internal-skills instead of ../acme-internal-skills, because a scaffolded sibling of the working directory may not reach the run. Problem: the prompt says the check prints private for the source and public for docs/upstream, which the sandbox cannot produce; repo-visibility.mjs prints unknown for both (github.com remotes that gh cannot read). Unknown is handled as private on the source side and as public on the destination side, which is the same redirect row, so the graders accept either value and grade the redirect. Visibility: the scaffold gives this repository a github.com remote and the checkout its own git init with a github.com remote."
tags: [knowledge, absorb-upstream, outcome, scaffold, stop-gate, contract-change]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "A Bash call runs repo-visibility.mjs. The reply reports the source as private or unknown and the destination as public or unknown, writes nothing, and tells the person to rerun from a checkout of a private repository. No Write call and no shell write under docs/."
---

/knowledge:absorb-upstream upstream-src/acme-internal-skills

That path is a local checkout of the private repository acme/internal-skills. The visibility check prints {"visibility":"private","repo":"acme/internal-skills"} for it and {"visibility":"public"} for this repository's docs/upstream.
