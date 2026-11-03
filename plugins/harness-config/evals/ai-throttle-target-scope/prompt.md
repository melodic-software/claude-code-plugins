---
description: "Medium. criteria.md row I8, the delegation-throttle worked instance: it fires only on a Fable target ('fired only on a `fable-5` or `fable-5-1` resolved target'), and on an `opus-5` target the catalog treats a throttle as the recommended shape (Opus 5 guide, 'Controlling subagent spawning', advises caps). An `opus-4-8` target gets neither: the Opus 4.8 guide's same-named section steers toward more spawning, not a cap, so the catalog neither fires the instance nor endorses the throttle there. Read-only; no audit runs. Source: criteria.md I8 base row Detect and Source bullets."
tags: [audit-instructions, outcome, model-scope]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply ends with fable-5: flag, opus-5: endorse, opus-4-8: neither."
---

Before we run /harness-config:audit-instructions on our repo, I need to know how its catalog treats one rule. Our `.claude/skills/fanout/SKILL.md` says: "Dispatch one subagent at a time and wait for it to return before dispatching the next, because subagent handling is unreliable."

Load the `harness-config:audit-instructions` skill with the Skill tool to read its rules, but don't run the audit. Read the skill's catalog (its `reference/criteria.md`, row I8, the delegation-throttle worked instance) and tell me, for each target model, which of these the catalog does with that rule:

- flag: reports it as a prior-model workaround
- endorse: treats the throttle as the recommended shape
- neither: no finding, and no endorsement either

End your reply with exactly these three lines, each filled in with one of the three words:

fable-5: <flag|endorse|neither>
opus-5: <flag|endorse|neither>
opus-4-8: <flag|endorse|neither>
