---
description: "Scenario T4, turn 2: setup apply on the legacy tarnquill copy after turn 1's check. turn-1.jsonl holds turn 1 as text only: the check prompt and a report, rewritten from a committed labeled sample, that names .claude/developer-experience.md as an old location and lists migrate as the next apply, with no Skill or Bash call recorded. Grades items 5-7: the conventions file is created at docs/conventions/developer-experience.md and the old file removed, AGENTS.md holds exactly one pointer line and it names the new path, and CLAUDE.md stays byte-identical to the scaffold. The old file's removal is graded on the Bash call that removes or moves it, since file_exists sees only files the run created. A path target runs a history_file case single-arm; pass --ablation with-without to compare. A run needs --scaffold and --allow-tools Write Edit Bash; the source scenario grants Bash(dotnet:*), Bash(git:*), Bash(make:*) and Bash(bash scripts/*)"
tags: [setup, pass-fail]
max_turns: 40
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "docs/conventions/developer-experience.md is created and .claude/developer-experience.md removed; AGENTS.md holds exactly one pointer line, naming docs/conventions/developer-experience.md; CLAUDE.md is byte-identical to the scaffold"
---

/developer-experience:setup apply. I confirm the changes it shows.
