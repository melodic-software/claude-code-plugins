---
description: "Scenario T3: setup apply on the bare brackenfold copy, whose `bfk release` asks for confirmation. Both arms get the same slash prompt, so the no-plugin arm is not the scenario's plain-language baseline. The conventions-file graders read the plugin's default path and are with-only. Their judge samples are the labeled AGENTS.md diffs (sources/labels/T3/), and the judges are not yet calibrated against them"
tags: [setup, task-outcome]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "AGENTS.md keeps every line it had and gains exactly one pointer line naming docs/conventions/developer-experience.md. That file names only commands, scripts and helpers the repository has, records `bfk release` as interactive or leaves it out, and claims no flag that skips its confirmation outside `## Not yet`"
---

/developer-experience:setup apply. I confirm the changes it shows.
