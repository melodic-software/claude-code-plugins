---
description: "An empty-argument explain with no earlier assistant message has no referent to drop to plain words, so it asks what to explain instead of inventing a topic"
tags: [education, explain, outcome, anaphora]
max_turns: 6
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "A short reply that asks what the user would like explained, with no invented explanation and no /education:teach handoff line."
---

/education:explain
