---
description: "Hard case. Why hard: The validator exists only in this plugin (names-validator is self-reference); the base model reaches for a --runs 1 smoke test, which costs money and reads a scoring case as proof it loaded."
tags: [validation, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer names the static validator (validate-cases.py or /evals:validate), names `timeout_seconds` as the key, and says `contains` is not a grader type (use `type: regex`)"
---

Before I pay for a plugin eval run, I'd like to know the cases will even load. One case's prompt.md frontmatter has `timeout: 600`, and one grader file says `type: contains` with a `pattern`. Is there a check that costs nothing, and are those two lines a problem? Answer in under 150 words.
