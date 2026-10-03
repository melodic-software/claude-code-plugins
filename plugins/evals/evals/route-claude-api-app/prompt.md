---
description: "Hard case. Why hard: The base model writes its own harness (pytest, promptfoo) and has no reason to know the bundled claude-api skill's build-eval subcommand; the blind base answers never named it. The did-not-start guard is an unscored with-only indicator; the rubric fails an answer that says it started build-eval."
tags: [routing, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer's main route for this service's first eval suite is the bundled claude-api skill's build-eval (`/claude-api build-eval`), and no Skill call starts build-eval"
---

Our repo is a small Python service: a FastAPI endpoint passes each incoming support email to Claude using the `anthropic` package and gets back a priority label. We have no evals at all yet. What's the right way to get evals in place here? Answer in under 150 words.
