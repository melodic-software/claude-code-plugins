---
description: "Locate code: the function that scans an eval grader's regex for Python-only tokens"
tags: [routing, retrieval]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep]
expected_outcome: "Names plugins/evals/skills/validate/scripts/validate-cases.py and its python_only_tokens function."
---

The current directory holds a snapshot of two plugins from a Claude Code plugin repository. Answer from its files.

An eval grader's regex runs under JavaScript, so a static check reports any Python-only syntax in it, such as `\A` or a possessive quantifier, before a paid run. Which function scans a pattern and returns the Python-only tokens it finds, and in which file? Reply with the file path from the current directory and the function name.
