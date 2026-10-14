---
description: "A markdown-only illustrate of a real module reads the file first and prints a record of several small mermaid diagrams whose labels carry the module's actual rules, with the file listed under sources and no HTML page"
tags: [education, illustrate, outcome, grounding, scaffold]
max_turns: 12
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "src/retry.js is read; the printed record holds at least two mermaid blocks, states the four-attempt cap, the 429 retry, the other-4xx give-up and the 5xx retry, lists src/retry.js under sources, and contains no HTML page."
---

/education:illustrate how src/retry.js decides when to give up markdown terminal

This run cannot write files or run scripts, so print the complete markdown record in your reply instead of building it.
