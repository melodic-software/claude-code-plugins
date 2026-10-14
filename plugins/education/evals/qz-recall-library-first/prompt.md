---
description: "recall searches the retained report library before git or tracker archaeology, names the library's coverage boundary (only quizzed work), and does not invent a library hit"
tags: [education, quiz-me, outcome, recall]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply reports the library result first, says the library holds only work that was quizzed, then names the git history or tracker fallback and what it found, without claiming a report was found."
---

/education:quiz-me recall what did we do on the auth rate-limit ordering change
