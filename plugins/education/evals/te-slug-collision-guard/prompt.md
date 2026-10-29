---
description: "teach derives <project-slug> as the canonical project basename plus an 8-hex sha256, and guards a topic slug collision: a new C# topic whose slug `c` is taken by an existing C++ workspace gets `c-` plus a 4-hex hash of its raw name"
tags: [education, teach, outcome, project-slug, scaffold]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The existing topic/c/MISSION.md is read, sha256 of the raw name C# is computed with sha256sum or shasum, and the reply gives the new workspace path as learning-root/<basename>-<8 hex>/topic/c-<4 hex>."
---

/education:teach topic C#

Goal: read and fix the C# services at work. Success looks like shipping one bug fix in a C# service without help. Constraint: about an hour a week. This repository's CLAUDE.md declares the teach workspace root. This run cannot write files, so print the full path of the workspace directory you would create for this topic and show how you derived each part of it.
