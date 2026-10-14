---
description: "A user-invoked quiz-me on a finished diff prints the report with context, intuition, decisions and what-was-done sections in that order, the quiz at the bottom with each question anchored to a section, and the answer key after it"
tags: [education, quiz-me, outcome, report, scaffold]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The diff is read; the printed markdown report has Context, Intuition, Decisions and What was done headings in that order, then a Quiz heading with no narrative section after it, at least three questions each naming the section that teaches its answer, an answer key after the quiz, and diff specifics (PUBLIC_PATHS or /health, the 401 or invalid_token path, the rate limiter)."
---

/education:quiz-me on the auth middleware change in evals/fixtures/auth-middleware-change/auth-middleware.diff, which we just finished.

This run cannot write files or run scripts, so print the full report as markdown in your reply.
