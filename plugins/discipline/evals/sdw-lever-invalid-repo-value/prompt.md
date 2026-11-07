---
description: "Legacy script-the-deterministic-work 11. The scaffold writes docs/conventions/discipline.yaml with the invalid lever_scope: always; the prompt gives the user option as non-trivial. invalid-value-named, scope-default, not-user-value (not_contains) and answers-edit are regex; completes-check (llm) quotes legacy expectations 3-4. Needs --scaffold."
tags: [discipline, script-the-deterministic-work, outcome, lever-check, scaffold, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Names docs/conventions/discipline.yaml lever_scope: always as invalid, resolves the default deterministic (not the user's non-trivial), and answers edit-by-hand for the per-component class naming."
---

/discipline:script-the-deterministic-work lever-check in 18 React components, move each inline style object into the component's CSS module, picking class names that fit each component

[My lever_scope option is non-trivial. The repository is a git checkout, not the home directory, and docs/conventions/discipline.yaml holds `lever_scope: always`.]
