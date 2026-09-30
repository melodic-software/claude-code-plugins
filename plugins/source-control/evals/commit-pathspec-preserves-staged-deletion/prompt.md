---
description: Commit two named paths on a shared index, one of them a staged deletion that must survive the pathspec form
tags: [commit, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The commit uses the pathspec form, reads the staged deletion from git diff --cached --name-status, and never deletes the file from disk
---

Another Claude Code session has unrelated files staged on this same branch. I've already run `git rm --cached config/local-secrets.yaml` (it's staying on disk, just added to .gitignore) and staged an edit to src/app.ts. Commit only my two paths (config/local-secrets.yaml and src/app.ts) without touching the other session's staged work.
