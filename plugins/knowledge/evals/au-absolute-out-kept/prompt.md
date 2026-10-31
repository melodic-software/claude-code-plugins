---
description: "Ported from plugins/knowledge/skills/absorb-upstream/evals/evals.json id 10 (absent at base: head-side expectation; a base failure is the old contract). Base rejects any absolute --out: MB:plugins/knowledge/reference/config.md:32 (not absolute) and MB:plugins/knowledge/skills/absorb-upstream/SKILL.md:25 and :40-44 (an absolute value is invalid, the layer is dropped). Covers lost sentences 3 and 9 (absolute --out in a private destination), 7 and 8 (local-checkout source) and 15 (report names both visibilities). The source path is upstream-src/acme-internal-skills instead of ../acme-internal-skills, because a scaffolded sibling of the working directory may not reach the run. Problems: the prompt says the check prints private for both sides; the sandbox prints unknown for the source and local for /srv/repos/acme-corpus/docs/upstream (no such directory and no git repository above it). Head keeps an absolute --out that reads local, so the kept-from-the-argument-layer outcome is reachable; id 10's 'writes the record at /srv/repos/acme-corpus/docs/upstream/acme-internal-skills.md' is not (the run cannot fetch the upstream-drift convention, and the sandbox cannot write under /srv), so it is graded only as a must-not: no write in this repository. Visibility: the scaffold runs git init with no remote here and gives the checkout its own git init with a github.com remote."
tags: [knowledge, absorb-upstream, outcome, scaffold, config-layer, contract-change]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply reports the record directory /srv/repos/acme-corpus/docs/upstream from the argument layer and does not call it invalid. A Bash call runs repo-visibility.mjs on that directory. The reply reports the source as private or unknown and the destination as private or local. No Write call targets a path outside /srv/repos/acme-corpus/."
---

/knowledge:absorb-upstream upstream-src/acme-internal-skills --out /srv/repos/acme-corpus/docs/upstream

That path is a local checkout of the private repository acme/internal-skills. /srv/repos/acme-corpus is a checkout of the private repository acme/corpus. The visibility check prints {"visibility":"private","repo":"acme/internal-skills"} for the source and {"visibility":"private","repo":"acme/corpus"} for /srv/repos/acme-corpus/docs/upstream.
