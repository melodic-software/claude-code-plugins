---
description: "Scenario T4, turn 2: setup apply on the legacy tarnquill copy after turn 1's check. turn-1.jsonl holds turn 1 as text only: the check prompt and a report, rewritten from a committed labeled sample, that names .claude/developer-experience.md as an old location and lists migrate as the next apply, with no Skill or Bash call recorded. Grades items 6-7 and the creation half of item 5: the conventions file is created at docs/conventions/developer-experience.md, AGENTS.md holds exactly one pointer line and it names the new path, and CLAUDE.md stays byte-identical to the scaffold. The old file's removal is unmeasured: .claude/ is a protected path, so the eval sandbox denies its removal and that denial fails the run, and the prompt keeps the file. A path target runs a history_file case single-arm; pass --ablation with-without to compare. A run needs --scaffold and --allow-tools Write Edit Bash; the source scenario grants Bash(dotnet:*), Bash(git:*), Bash(make:*) and Bash(bash scripts/*)"
tags: [setup, pass-fail]
max_turns: 40
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "docs/conventions/developer-experience.md is created; .claude/developer-experience.md is left in place as the user asked; AGENTS.md holds exactly one pointer line, naming docs/conventions/developer-experience.md; CLAUDE.md is byte-identical to the scaffold"
---

/developer-experience:setup apply. I confirm the changes it shows, except removing `.claude/developer-experience.md`: leave that file in place, I will delete it myself.
