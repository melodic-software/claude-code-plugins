---
description: "setup check validates only the compress settings: the scaffold's docs/conventions/docs-hygiene.yaml sets compress_articles: cut, and its package.json names markdownlint-cli2 without installing it. The run must run setup-apply.mjs --check, report the PASS compress_articles: cut row, never probe or run markdownlint, and write nothing. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: [setup, settings, read-only, scaffold]
runs: 3
max_turns: 15
timeout_seconds: 300
allowed_tools: [Skill, Read, Write, Edit, Glob, Grep, Bash]
expected_outcome: "Runs setup-apply.mjs --check, reports PASS compress_articles: cut and an effective compress_articles of cut from the repository file, runs no markdownlint command, and edits or writes no file."
---

/docs-hygiene:setup check
