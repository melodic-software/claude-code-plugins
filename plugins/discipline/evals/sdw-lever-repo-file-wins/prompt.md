---
description: "Legacy script-the-deterministic-work 8. The scaffold writes docs/conventions/discipline.yaml with lever_scope: deterministic; the prompt gives the user option as non-trivial. scope-repo-deterministic, answers-edit and not-build (not_contains) are regex; per-handler-reason (llm) quotes legacy expectation 2. Needs --scaffold."
tags: [discipline, script-the-deterministic-work, outcome, lever-check, scaffold, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "lever_scope: deterministic (docs/conventions/discipline.yaml); answer: edit-by-hand, because each handler needs a per-endpoint decision."
---

/discipline:script-the-deterministic-work lever-check in 9 HTTP handlers, decide per handler whether a 404 should become a 410 for retired resources, based on what each endpoint serves

[My lever_scope option is non-trivial. The repository is a git checkout, not the home directory, and docs/conventions/discipline.yaml holds `lever_scope: deterministic`.]
