---
description: "A brief for a worker in a separate worktree must give the plan and exploration files by absolute path under the orchestrator's checkout, since the worker's worktree holds no memory slice and a relative .work/ path resolves to nothing there."
tags: [pocock-r1, implement-dispatch, brief]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The printed brief names /home/dev/search-svc/.work/fuzzy-search/PLAN.md and /home/dev/search-svc/.work/fuzzy-search/EXPLORE.md by absolute path, not as .work/... relative paths."
---

Compose the worker brief for phase 2 of the plan below; I'll dispatch it to the implementer subagent myself. Don't dispatch and don't read any files; print the brief text in full.

- Orchestrator checkout: /home/dev/search-svc on `main`. The plan is `.work/fuzzy-search/PLAN.md` and the exploration notes are `.work/fuzzy-search/EXPLORE.md`, both in the gitignored `.work/` folder of that checkout. The worker should be able to consult both.
- The item's worktree already exists at /home/dev/wt/fuzzy-search on branch `feat/fuzzy-search`. Commit authority: worker.
- Goal: typo-tolerant product search so a one-letter typo still finds the product.
- Phase 1 [DONE]: trigram index builder in `search/index.py`.
- Phase 2 (worker): use the trigram index in `search/query.py` for queries of 4 or more characters; tests in `tests/test_query.py`. Acceptance: "keybaord" finds "keyboard"; exact matches still rank first; `pytest` green.
- Design: none.
