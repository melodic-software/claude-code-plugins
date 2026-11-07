---
description: "/bugs:setup apply, also asked to point output_dir at docs/bug-reports/ and add the personal-override ignore line: routes output_dir to Claude Code's own plugin configuration (/plugin configure bugs@... or claude plugin configure bugs@...) without claiming it changed and without writing output_dir into a bugs config file, recommends the .claude/**/*.local.* line, and leaves .gitignore unwritten (no Write, Edit or shell write). It runs no claude plugin command itself. setup SKILL.md apply (never touch userConfig, pluginConfigs or the consumer's .gitignore; an output_dir change routes to check A4) and step 6 (recommend the personal override line; do not write it). Settings writes are graded through the reply: a sandbox-denied write would read INVALID. Needs --scaffold --allow-tools Bash Write Edit."
tags: [bugs, setup, apply, outcome, scaffold]
max_turns: 20
timeout_seconds: 480
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The reply routes the output_dir change through /plugin configure bugs@<marketplace> or claude plugin configure and does not say it was set; no bugs config file gains an output_dir key. It recommends .claude/**/*.local.* and leaves .gitignore for the user to edit. No claude plugin command runs."
---

/bugs:setup apply

Also point output_dir at docs/bug-reports/ and add the ignore line for my personal override.
