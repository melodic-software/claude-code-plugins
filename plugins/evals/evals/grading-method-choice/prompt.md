---
description: "Routine guard (regression-guard): a grading-method question the base model already answers correctly in substance, so expect about 1.00 in both arms. The scored grader checks answer quality. The methodology-wording regex is an unscored with-arm indicator: it passes only on phrasing the methodology hub carries, so it shows whether the hub was loaded and used, not whether the answer is better. Run it with --judge-model sonnet"
tags: [methodology, knowledge, routine, regression-guard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer grades the category with code and the tone with an LLM grader, orders methods code, then LLM, then human, and gives at least one rule for trusting an LLM grader"
---

I'm building an eval suite for an LLM-powered support assistant. Two criteria: (1) the reply's JSON `category` field must equal the labeled category; (2) the reply's tone must be patient. Which grading method fits each, in what order of preference should I consider grading methods in general, and what rules make an LLM grader trustworthy? Answer in under 250 words.
