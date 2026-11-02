---
description: "Scenario S1 (branch workflow), build turn. turn-1.jsonl holds turn 1 as text only: the prompt and the final message of a recorded plugin-arm plan turn for tq branch start that changed nothing, with its tool calls, the Skill call included, left out. The run builds the command after the yes. Free graders cover items 1 (a Write call runs git through ProcessRunner.Run), 2 (no Write or Edit adds Process.Start or ProcessStartInfo outside Infrastructure/ProcessRunner.cs), 3 (the conventions Tools section names branch start), 8 (a written file names TARNQUILL_FORGE_TOKEN and calls GetEnvironmentVariable, and no Write or Edit reads a --token or --forge-token option from args), 11a (a shell call runs tq branch start), 11b (a judge reads whether the final message states the smoke result), 12a (make check or the checks project runs), 12b (the final message names the PageCount or paging failure) and 12c in part (the files list holds a .cs file the run created under src/Tarnquill.Cli/). Item 10, turn 1, is graded live by s1-branch-start-plan. Items 4-7 and 9 run the built command, which no grader type can do. A path target runs a history_file case single-arm; pass --ablation with-without to compare. A run needs --scaffold and --allow-tools Write Edit Bash; the source scenario grants Bash(dotnet:*), Bash(git:*), Bash(make:*) and Bash(bash scripts/*)"
tags: [build-cli, s1, build-turn]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "tq branch start is built in a new file under src/Tarnquill.Cli/ that runs git through ProcessRunner.Run and reads the token from TARNQUILL_FORGE_TOKEN, no other file starts a process, the conventions Tools section names the command, and the run executes tq branch start and make check"
---

Yes, go ahead.
