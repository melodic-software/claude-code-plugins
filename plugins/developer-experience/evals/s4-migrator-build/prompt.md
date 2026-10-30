---
description: "Scenario S4 (data-migration helper), build turn. turn-1.jsonl holds turn 1 as text only: the prompt and a plan for bfk migrate that changes nothing and asks which backup format to use, with no Skill call recorded. The second turn is the source scenario's \"Yes, go ahead.\", which leaves that question open. Free graders cover items 6 (the conventions Tools section names the migration), 7 in part (pyproject.toml still declares no dependency) and 9a (a shell call runs the helper, not only its tests). Items 8 and 10, turn 1, are graded live by s4-migrator-plan. Items 1-5 run the built helper (item 4's judge reads that run's output), and the non-standard-library-import half of 7 reads every new module, which no grader type can do. Item 9b is a judge item whose committed labels grade a two-turn report from the no-plugin arms, not this turn's final message, so it is not graded here. A path target runs a history_file case single-arm; pass --ablation with-without to compare. A run needs --scaffold and --allow-tools Write Edit Bash; the source scenario grants Bash(python3:*), Bash(git:*), Bash(make:*) and Bash(bash scripts/*)"
tags: [build-cli, s4, build-turn]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "The migration helper is built with the standard library only, the conventions Tools section names it, pyproject.toml still declares no dependency, and the run executes the helper itself"
---

Yes, go ahead.
