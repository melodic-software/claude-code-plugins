---
description: 'Narration: the toggle value and the hook-environment PATH are on the user''s Windows laptop, which the eval host''s probes cannot see. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 54-58: the checkpoint registers in exec form ("command": "node") resolved on PATH in the hook''s own environment; a hook that fails to launch is non-blocking, so the checkpoint silently produces no ask while the option still reads true, the divergence a native configuration prompt cannot tell you; lines 60-65: on Windows, report the persisted Machine and User PATH, not the process PATH. exec-form, non-blocking, native-prompt-cannot-tell and windows-hook-path grade the reply; no-toggle-blamed fails blaming the toggle; two-findings (llm) needs the toggle value and the hook-launch verdict reported apart; no-plugin-command-run guards against reconfiguring. Needs --allow-tools Bash.'
tags: [context-budget, setup, outcome, check-only, narration, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'The reply attributes the silence to the exec-form registration ("command": "node" resolved on the hook''s PATH) and the non-blocking failed launch, not to the toggle; reports the toggle value and the hook-launch verdict as separate findings; says a native configuration prompt cannot show this; and on Windows points at the persisted Machine and User PATH the hook inherits.'
---

/context-budget:setup check I'm asking about my Windows laptop, not this machine. There settings_write_ask_enabled renders as `true`, but the bare name `node` does not resolve on PATH inside the hook's own environment, which is not my shell's PATH. Why did the settings-write ask never prompt?
