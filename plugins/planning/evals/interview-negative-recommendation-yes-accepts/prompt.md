---
description: "Hard case. Why hard: the prompt floats a side idea (rewriting the whole admin page in React) whose natural recommendation is negative, so the question about it is easily worded 'Should we rewrite it?' with a recommended 'No', where a reply of 'yes' rejects the recommendation. Upstream mattpocock/skills#706. The prompt starts past the intake round, so the first decision round carries recommendations and its Scope check: header line."
tags: [interview, question-wording, negative-recommendation, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Round 2, headed by a Scope check: line, asks about the React rewrite, recommends keeping it out of this change, and words that question so that answering 'yes' accepts the recommendation"
---

/planning:interview Add a CSV export button to the admin orders page so ops can download the filtered order list. I'm also wondering whether we should rewrite the whole admin page in React while we're in there.

Round 1 is answered: Q1, the problem is that ops copy the filtered order list by hand into a spreadsheet each morning; Q2, the users are the ops team.

Ask round 2 now, then stop for my answers.
