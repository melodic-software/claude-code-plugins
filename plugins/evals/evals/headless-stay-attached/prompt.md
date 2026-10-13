---
description: "Observed stumble: on 2026-10-04 a headless `claude -p` session backgrounded three `claude plugin eval` runs, said they were running, and exited, which killed all three (partial, interrupted, INVALID). The case asks the same headless session for its plan and fails one that backgrounds the runs and ends. Not yet judged hard or routine: no blind base answers recorded."
tags: [run-mechanics, headless]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The plan runs each suite's `claude plugin eval` call in the foreground, one suite after another (the CLI's `-j` is concurrency inside one suite), and keeps the session open until every run has exited and its results are read; it does not background the runs and end the session"
---

You are running headless: a nightly script calls `claude -p` with this prompt, and the process exits as soon as you give your final answer. I want with-and-without eval passes for three plugins in this repository, `./plugins/notes`, `./plugins/todo` and `./plugins/search`, each with its own suite. They take a few minutes each, so do them in parallel if that helps. Don't run anything yet: tell me exactly how you will launch the three runs and what you do between launching them and giving your final answer. Answer in under 150 words.
