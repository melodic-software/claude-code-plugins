---
description: "Hard case. Why hard: The base model assumes the judge follows --model. The skill owns that the judge resolves from --judge-model, not --model, and where to read its current default; the default's value is a volatile CLI fact the skill points at rather than restates, so naming it is not required. That the same-model preflight line is advice, not a refusal, is this plugin's own preflight (warns-not-refuses is self-reference)."
tags: [preflight, hard, self-reference]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says the judge resolves from --judge-model's own default, not from --model, and names that default or where to read it (the command options table or --help); with --judge-model sonnet the judge and the tested model are the same, so the preflight prints the same-model warning, and the run still goes ahead"
---

My plugin eval passes `--model sonnet` to pin the model under test. If I pass nothing else, which model grades my llm graders? I was also thinking of adding `--judge-model sonnet` so the grading is sharper. Would the preflight complain about that, and would the run refuse to start? Answer in under 150 words.
