---
description: "Prototype-bar design for a throwaway recipe-import spike: the first round skips the one-way and two-way door calls and says reversibility is deferred, and writes no code"
tags: [design, reversibility, quality-bar, prototype, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The first design round says the lifecycle and reversibility pass is skipped or deferred because the quality bar is prototype, and classes no decision as a one-way or two-way door. No .py file is written or edited"
---

/planning:design module

Topic slug `recipe-import`; the Brief is in `.work/recipe-import/PLAN.md`. Run the first discussion round with your recommendations, then stop for my answers. Don't write any code.
