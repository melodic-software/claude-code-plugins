---
description: "Hard case. Why hard: the prompt floats a side idea (rewriting the whole admin page in React) whose natural recommendation is negative, so the question about it is easily worded 'Should we rewrite it?' with a recommended 'No', where a reply of 'yes' rejects the recommendation. Upstream mattpocock/skills#706."
tags: [interview, question-wording, negative-recommendation]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 1 asks about the React rewrite, recommends keeping it out of this change, and words that question so that answering 'yes' accepts the recommendation"
---

/planning:interview Add a CSV export button to the admin orders page so ops can download the filtered order list. I'm also wondering whether we should rewrite the whole admin page in React while we're in there.
