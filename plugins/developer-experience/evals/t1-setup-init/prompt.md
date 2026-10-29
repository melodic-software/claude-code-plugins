---
description: "Scenario T1 (setup init) on the bare tarnquill fixture. Scored in both arms: the conventions reach AGENTS.md (C1, approximated as AGENTS.md naming a markdown file other than README, AGENTS or CLAUDE, or holding at least 10 non-blank lines) and no scaffold AGENTS.md line is changed or removed (C4). Scored in the plugin arm only, since they read docs/conventions/developer-experience.md: every backticked path there names a fixture file and a judge finds every named command, script and helper real (C2), tq commit stays interactive (C3), and P1-P5 (the file, its written_against front matter, a source marker under every section but Not yet, one pointer line, AGENTS.md changed only by the managed block). The C2 and C3 judge samples are the labeled baseline-arm AGENTS.md diffs. Both arms get this slash prompt, unlike the scenario's baseline arms, which got a natural-language prompt, so the delta is not the scenario's arm comparison"
tags: [setup, t1]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "setup writes docs/conventions/developer-experience.md (written_against front matter, a source marker under every section but Not yet, tq commit recorded as interactive, only real commands, scripts and helpers named) and adds the managed pointer block to AGENTS.md through its helper, leaving every other AGENTS.md line as it was"
---

/developer-experience:setup apply. I confirm the changes it shows.
