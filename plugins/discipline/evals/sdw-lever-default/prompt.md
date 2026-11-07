---
description: "Legacy script-the-deterministic-work 9 (narration: no user option, no repo file). scope-default, answers-build and pilot-diff are regex; no-write and no-edit (max 0, both arms) check the YAML files are not edited; mechanical-and-pilot (llm) quotes legacy expectations 2-3. Needs --allow-tools Write Edit so the no-edit graders can fail."
tags: [discipline, script-the-deterministic-work, outcome, lever-check, narration, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit]
expected_outcome: "lever_scope: deterministic (default); answer: build-a-lever (a throwaway script is enough for a key rename); rename one file by hand, run the script on a clean copy and diff before the other 30. No file edited."
---

/discipline:script-the-deterministic-work lever-check rename the config key `retryLimit` to `maxRetries` in 31 YAML files under deploy/

[No lever_scope option is set and the repository, a git checkout that is not the home directory, has no docs/conventions/discipline.yaml.]
