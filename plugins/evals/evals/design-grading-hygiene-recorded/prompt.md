---
description: "The design skill's Phase 3 grading hygiene gate: with every criterion settled up front, the criteria doc names a grader model different from the model under test for each LLM-graded check and states what a re-run costs. Written from MB:plugins/evals/skills/design/SKILL.md:213-222."
tags: [design, grading-hygiene]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply holds a criteria doc that names a judge or grader model other than Claude Sonnet for the LLM-graded tone check, and states the re-run cost, separating the free code-graded checks from the metered LLM-graded ones."
---

/evals:design My support-reply drafter calls Claude Sonnet to draft answers to customer emails. The success criteria are already agreed with the team, so do not ask me anything: tone scores at least 4 on our 5-point tone rubric, judged by an LLM grader; every reply cites a knowledge-base article ID, checked by a regex; and replies stay under 180 words, checked by a word count. Today's baseline is 3.2 on tone and 71% of replies citing an article. Write the criteria doc in your reply; do not write any file.
