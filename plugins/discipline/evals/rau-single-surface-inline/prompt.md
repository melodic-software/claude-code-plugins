---
description: "Legacy recheck-against-upstream 8. One changed setting in one file (given in the prompt). no-agent and no-task (max 0, both arms) check no subagent is dispatched; stays-inline (llm) quotes legacy expectations 1-3. The run has no network, so the recheck cannot reach a clean verdict; watch: a run that calls it clean and dispatches the method doc's confirmation subagent fails the legacy no-Agent expectation. Read-only."
tags: [discipline, recheck-against-upstream, outcome, narration, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Runs the inline recheck on the one setting with no subagent and no fan-out, reporting what it could and could not compare."
---

/discipline:recheck-against-upstream I just changed one setting in one config file; check it against the docs.

(The file is tsconfig.json; I changed `"module"` from `"CommonJS"` to `"NodeNext"` and nothing else. The project pins TypeScript 5.6.3.)
