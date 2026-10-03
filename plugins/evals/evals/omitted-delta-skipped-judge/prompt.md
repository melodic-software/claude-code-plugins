---
description: "Hard case. Why hard: Both are runner semantics: the base model reads a missing delta as no change and a skipped grader as unscored; the blind best-guess answers got the delta right and the skipped grader wrong."
tags: [reading-results, hard]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The answer says an omitted delta is never 0 (the arms were not comparable, so report the case as not comparable), and a skipped judge grader is scored as a failure that pulls the arm down, so it cannot be ignored"
---

Reading my plugin eval's aggregate-result.json: one case has no `delta` field at all, and in a few of its with-plugin runs `skippedPaidGraders` is true and the llm grader's explanation reads 'skipped: cost ceiling'. partial is false and the exit code was 0. Can I count the missing delta as 0 and just ignore the skipped grader when I report the suite? Answer in under 150 words.
