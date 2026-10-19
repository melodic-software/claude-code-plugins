---
description: "Phase-boundary review escalation: in an unattended run, a re-review that rates the same finding CRITICAL again is logged to DEVIATIONS.md as a blocking human-decision and escalated once; no third fix or review, and the phase is not marked [DONE]."
tags: [implement-dispatch, phase-boundary, review-tags, read-only, unattended]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply writes a DEVIATIONS.md entry typed human-decision and marked blocking that names api/search.py:42 and the escape_like fix that was tried, parks the run without marking Phase 4 [DONE], and dispatches no further fix brief or review."
---

/implementation:implement-dispatch phase-4 Don't dispatch anything, don't read files and don't run commands. Print the `DEVIATIONS.md` entry you append now, then say in one or two lines what the run does next, then stop.

The run is autonomous with nobody to answer. The approved plan's Phase 4 adds a search endpoint; its header reads:

```markdown
### Phase 4: Search endpoint [TODO]
Review: security
```

Phase 4's worktree is `/srv/wt/shop-search` on branch `feat/search`; the previous phase-boundary commit is `0e7c41a9b3d25f68c1e90a4d7b2f3c5e8a6d1b09`.

What has happened at this boundary:

1. The first `/review:quality-gate security` call returned one CRITICAL finding: `api/search.py:42` builds the SQL query by concatenating the `q` request parameter.
2. One fix brief went out under Phase 4's fence. The worker's fix passes `q` through `escape_like()` and still concatenates; it passed the build/test gate and was committed as `9c2e5d71f4a08b36e1d9c7a2f5b40e83d6a1c2f7`.
3. The one re-review, with the same `--base` as the first call, rates the same finding CRITICAL again: `api/search.py:42` still concatenates `q` into the SQL text.
