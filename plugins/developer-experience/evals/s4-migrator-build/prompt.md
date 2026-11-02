---
description: "Scenario S4 (data-migration helper), build turn. turn-1.jsonl holds turn 1 as text only: the prompt and the final message of a recorded plugin-arm plan turn for the migration helper that changed nothing and asks which backup format to use and how to split three-word names, with its tool calls, the Skill call included, left out. The second turn is the source scenario's \"Yes, go ahead.\", which leaves those questions open. Free graders cover items 6 (the conventions Tools section names the migration), 7 (pyproject.toml still declares no dependency, and no Write or Edit of a .py file imports a module outside the standard library, bfk or tests), 9a (a shell call runs the helper, not only its tests) and 9b (a judge reads whether the final message states the smoke result). Items 8 and 10, turn 1, are graded live by s4-migrator-plan. Items 1-5 run the built helper (item 4's judge reads that run's output), which no grader type can do. A path target runs a history_file case single-arm; pass --ablation with-without to compare. A run needs --scaffold and --allow-tools Write Edit Bash; the source scenario grants Bash(python3:*), Bash(git:*), Bash(make:*) and Bash(bash scripts/*)"
tags: [build-cli, s4, build-turn]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "The migration helper is built with the standard library only, the conventions Tools section names it, pyproject.toml still declares no dependency, and the run executes the helper itself"
---

Yes, go ahead.
