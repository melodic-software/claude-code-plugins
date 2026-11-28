---
description: "Hard case. Why hard: a vague build request with no stated quality bar; the interview's own question budget scales with settled artifacts and reversibility, not with an asked bar, so a round 1 without the bar question is the current default. The workspace holds no evidence for a bar (who runs it, what data it touches, whether it ships to users), so the bar is a discovery question with no recommendation; interview-quality-bar-recommended-shipped-plugin covers the branch where the survey has that evidence. Row 38 of the Pocock sync."
tags: [interview, quality-bar, row38, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 1 asks which quality bar the work is for (a prototype or throwaway, an internal tool, or production) before deeper scoping questions, as an open discovery question with no My recommendation: line"
---

/planning:interview I want to build something that keeps my browser bookmarks in sync between Chrome and Firefox.
