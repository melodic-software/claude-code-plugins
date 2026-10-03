---
description: "Hard case. Why hard: The base model assumes the judge follows --model; the default judge (haiku) is a CLI fact, and that the same-model preflight line is advice, not a refusal, is this plugin's own preflight (warns-not-refuses is self-reference)."
tags: [preflight, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says the default judge is haiku (a small fast model) whatever --model says; with --judge-model sonnet the judge and the tested model are the same, so the preflight prints the same-model warning, and the run still goes ahead"
---

My plugin eval passes `--model sonnet` to pin the model under test. If I pass nothing else, which model grades my llm graders? I was also thinking of adding `--judge-model sonnet` so the grading is sharper. Would the preflight complain about that, and would the run refuse to start? Answer in under 150 words.
