---
description: "Scenario S1 (branch workflow), build turn. turn-1.jsonl holds turn 1 as text only: the prompt and a plan for tq branch start that changes nothing, with no Skill call recorded. The run builds the command after the yes. Free graders cover items 1 (a Write call runs git through ProcessRunner.Run), 2 (no Write or Edit adds Process.Start or ProcessStartInfo outside Infrastructure/ProcessRunner.cs), 3 (the conventions Tools section names branch start), 8 in part (a written file names TARNQUILL_FORGE_TOKEN and calls GetEnvironmentVariable), 11a (a shell call runs tq branch start), 12a (make check or the checks project runs) and 12c in part (the files list holds a .cs file the run created under src/Tarnquill.Cli/). Item 10, turn 1, is graded live by s1-branch-start-plan. Items 4-7 and 9, and the no-token-option half of 8, run the built command, which no grader type can do. Items 11b and 12b are judge items whose committed labels grade a two-turn report from the no-plugin arms, not this turn's final message, so they are not graded here. A path target runs a history_file case single-arm; pass --ablation with-without to compare. A run needs --scaffold and --allow-tools Write Edit Bash; the source scenario grants Bash(dotnet:*), Bash(git:*), Bash(make:*) and Bash(bash scripts/*)"
tags: [build-cli, s1, build-turn]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "tq branch start is built in a new file under src/Tarnquill.Cli/ that runs git through ProcessRunner.Run and reads the token from TARNQUILL_FORGE_TOKEN, no other file starts a process, the conventions Tools section names the command, and the run executes tq branch start and make check"
---

Yes, go ahead.
