---
description: "Scenario S5 (build-cli review): a read-only review of `bfk release` reports its gaps against the team CLI contract, the interactive-only confirmation and the missing `--yes` bypass among them, cites file:line for each, and changes nothing"
tags: [build-cli, scenario]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "Lists the gaps in `bfk release` against the CLI contract, including that the input() confirmation makes it interactive-only and that no flag such as --yes bypasses it, each gap citing a file and line such as bfk/release.py:7; makes no Write or Edit call, deletes or moves nothing, and creates no file"
---

Review `bfk release` as a command-line tool. Don't change anything yet.
