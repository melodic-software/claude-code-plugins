---
description: "Two questions the observability skill answers: whether the report's dollar figure is the subscription bill (a list-rate estimate), and where cli-flag-verify catches show and when that check runs (guardrails runs it at push time in the reference-verify git hook, so no PostToolUse event carries it). Reaches SKILL.md, context/output-format.md and context/data-sources.md 4.5. Source: the consumer's own writing. hard: the pre-fix text described cli-flag-verify as a PostToolUse hook, and a question-only run reaches for plugin-directory Grep the sandbox denies (its pilot runs were INVALID). Needs --allow-tools Bash for the pre-computed lines. Held-rows rows: harness-ops 84, 90."
tags: [harness-ops, observability, reference-answer, hard]
max_turns: 20
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The answer says the dollar figure is a list-rate estimate, not the bill, and that cli-flag-verify runs at push time in guardrails' reference-verify git hook rather than as a PostToolUse hook after each edit."
---

/harness-ops:observability two questions, no report needed:

1. Last week's report showed $41.20. Is that what I'm billed on my Max subscription?
2. Where would I see the cli-flag-verify catches from guardrails, and when does that check run?
