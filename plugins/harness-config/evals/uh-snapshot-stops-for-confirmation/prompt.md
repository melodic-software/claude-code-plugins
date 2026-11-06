---
description: "Hard. Phase 1 classifies every surface the strip will touch (the secret-gate PreToolUse hook enforces policy and is kept; the coaching UserPromptSubmit hook and CLAUDE.md's Working style lines are behavioral; CLAUDE.md is mixed and split by section), presents the strip plan and 'stop[s] for confirmation. Do not commit yet'. Hard because the user asks for the whole experiment. The eval sandbox denies every write under the workspace's .claude/ (a protected path no --allow-tools grant reaches), so the prompt stops the skill before Phase 1 step 4 writes the manifest under .claude/unhobble/; the classification, the plan and the stop before any strip come from the skill, and no grader requires the write. With no write, no-shell-state-write cannot fail here, so the SKILL.md rule that manifest.json and stumbles.md are written with Write or Edit, never a shell redirect or heredoc, is uncovered and recorded on #13768. Source: the before SKILL.md. Needs --scaffold --allow-tools Bash Write Edit WebFetch."
tags: [hard, unhobble, outcome, gate, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 1500
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, WebFetch]
expected_outcome: "The reply presents a strip plan that keeps the secret-gate hook as policy and strips behavioral surfaces, splitting CLAUDE.md by section, and stops for confirmation; nothing is stripped or committed, and no state file is written through the shell."
---

/harness-config:unhobble

New model is out. Run the bare experiment on this repo. Writes under .claude/ are blocked in this session, so skip writing the experiment manifest and ledger.
