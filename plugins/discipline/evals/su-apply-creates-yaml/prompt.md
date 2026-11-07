---
description: "Legacy setup 4, without its narration: the scaffold makes the workspace its own git repository (AGENTS.md binds docs/conventions, so the script prints no convention-home offer) with no discipline.yaml. SKILL.md lines 133-143 and 182-187: check, write through setup-apply.mjs, re-check, then the tracked-file pair. check-before-write and recheck-after-write grade call order in the trace, reports-absent-info the INFO absent row, write-through-script the script call, yaml-written the new file's value, reports-pass the PASS row from the re-run, untracked-said the commit note, no-hand-write a shell write of the file, no-settings-bash and no-settings-read settings or pluginConfigs, no-other-file any other created path. Needs --scaffold and --allow-tools Bash, with a real node first on PATH."
tags: [discipline, setup, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "setup-apply.mjs --check, then setup-apply.mjs lever_scope=non-trivial, then --check again; docs/conventions/discipline.yaml holds lever_scope: non-trivial; the reply reports PASS lever_scope: non-trivial and says the file is untracked and must be committed."
---

/discipline:setup apply lever_scope=non-trivial
