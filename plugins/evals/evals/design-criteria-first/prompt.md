---
description: "Hard case. Why hard: The base model writes test cases straight away and lists unquantified criteria; this plugin's design skill interviews for criteria with a target number before any case, even when asked only for tests."
tags: [design, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Before any test case, the answer sets success criteria with at least one measurable target, proposed for the user to confirm or asked for, and asks the user at least one question about what success means or what baseline exists"
---

Our support-reply drafter uses a local Llama 3 model through Ollama to draft answers to customer emails. Can you write some evals for it? Answer in under 200 words.
