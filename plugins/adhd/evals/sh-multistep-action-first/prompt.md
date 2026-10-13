---
description: "With shape set, a multi-step how-to opens on an action, numbers the steps, has no preamble opener or pleasantry closer, and ends on one concrete next action"
tags: [adhd, shape, outcome, action-first]
max_turns: 6
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "First line is a command, path or imperative (no 'Great question', 'Sure', 'Let me'); the steps are a numbered list of at least three items; no 'hope this helps' or 'let me know' closer; the last line is a single concrete next action."
---

/adhd:shape

How do I set up a Python virtual environment for my project in ~/code/invoicer, install requests and pytest into it, and run the test suite?
