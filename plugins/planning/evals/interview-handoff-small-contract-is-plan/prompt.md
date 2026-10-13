---
description: "Contract case for the interview hand-off when the task is small, not design-significant, and the acceptance criteria already are the plan. Why hard: the natural reflex is to add a planning step that has nothing left to decide."
tags: [interview, handoff]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The user is told to go straight to implementation, because the locked acceptance criteria already serve as the plan and no separate planning or design step adds anything"
---

/planning:interview We just finished the interview for renaming the `--out` flag to `--output-dir` in our small internal CLI and updating its help text and two README lines. The Brief is locked, and its acceptance criteria list every file and the exact new wording, so there is nothing left to decide. No new types, contracts or modules. Hand off: what should I run next?
