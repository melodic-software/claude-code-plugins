---
description: "Hard case. Why hard: A base answer either thinks the runner loads CLAUDE.md, or proposes a headless A/B; this repository's route is to remove the instructions during real work and log where the model stumbles. preferred-route grades that house preference, and a plain A/B fails it by design."
tags: [target-routing, hard, house-preference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says no: every run starts from a throwaway home where CLAUDE.md and rules do not load, so a shim would measure the shim; the alternative is /harness-config:unhobble or, by hand, strip the instructions, log stumbles in real work, and restore only what repeated evidence earns"
---

Can `claude plugin eval` tell me whether the rules in our repo's CLAUDE.md and .claude/rules actually change how the model behaves? If not, what's the alternative? Answer in under 120 words.
