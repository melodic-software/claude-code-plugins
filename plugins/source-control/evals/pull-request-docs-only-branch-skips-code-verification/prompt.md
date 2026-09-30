---
description: A markdown-only branch owes the markdown audits and none of the code-class verification
tags: [pull-request, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: verification:confirm is never invoked for a diff that touches only README files
---

Prep this branch for a pull request. It only edits two README files, nothing else.
