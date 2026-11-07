---
schema_version: "1.1"
name: glossary-optimistic-update
description: "Routine: a described behavior (the like shows before the server confirms and flips back on failure) is named optimistic update, with waiting for the server as the contrast"
tags: [glossary, name-the-behavior, routine]
runs: 5
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply leads with optimistic update, defines it with the rollback, names waiting for the server as the contrast, and writes no implementation code"
---

When I click the heart on a post it turns red right away, even though the request to save the like hasn't come back yet. If the request fails it flips back. Is there a name for doing it that way?
