---
description: A grading-method question the methodology skill answers from its hub and grading reference
tags: [methodology, knowledge]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: The answer carries the methodology skill's own wording (the fastest-most-reliable-most-scalable rule, hand-graded showpieces, reading a sample of grader verdicts, the headline metric that hides regressions), which the base model does not emit unprompted
---

I'm building an eval suite for an LLM-powered support assistant. Two criteria: (1) the reply's JSON `category` field must equal the labeled category; (2) the reply's tone must be patient. Which grading method fits each, in what order of preference should I consider grading methods in general, and what rules make an LLM grader trustworthy? Answer in under 250 words.
