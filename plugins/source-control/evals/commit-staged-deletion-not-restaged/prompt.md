---
description: Commit two named paths on a shared index, one of them a staged deletion that must not be re-added or deleted from disk
tags: [commit, source-control]
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: The staged deletion is read from git diff --cached --name-status, the commit uses the pathspec form, and the path is never git-added over or removed from disk
---

Another Claude Code session has unrelated files staged on this same branch. I've already run `git rm --cached config/local-secrets.yaml` (it's staying on disk, just added to .gitignore) and staged an edit to src/app.ts. Commit only my two paths (config/local-secrets.yaml and src/app.ts) without touching the other session's staged work.
