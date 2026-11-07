---
description: "Legacy script-the-deterministic-work 7. The scaffold writes docs/conventions/discipline.yaml with lever_scope: non-trivial (the legacy narration made real); the prompt still says the user option is unset. scope-repo-non-trivial, answers-build and pilot-first-fixture are regex; placeholder-unset (llm) quotes legacy expectations 1 and 4. Needs --scaffold."
tags: [discipline, script-the-deterministic-work, outcome, lever-check, scaffold, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "lever_scope: non-trivial (docs/conventions/discipline.yaml); answer: build-a-lever; pilot on the first fixture before the rest."
---

/discipline:script-the-deterministic-work lever-check convert 22 test fixtures from assertEquals(expected, actual) to assertThat(actual).isEqualTo(expected), some of which pass a failure message as a third argument that must move into .as(...)

[My lever_scope option is unset (the placeholder is unexpanded). The repository is a git checkout, not the home directory, and docs/conventions/discipline.yaml holds `lever_scope: non-trivial`.]
