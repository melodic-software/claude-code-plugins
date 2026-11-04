---
description: "check with configs below the root and none at it. setup SKILL.md step 5 (lines 81-98): the opt-in is per-path; search the tree, skip node_modules, list nested configs with their directory scope; md_classify's flagged configs are INFO, gated. Legacy 'INFO, inactive: markdownlint-cli2 never runs under it' is corrected to lines 89-94: it runs only after the user approves that config state, and until then its files are neither rewritten nor checked; no-approval-marker guards line 94. The prompt asks whether the tool runs, not for a grade, so gated-info-needs-approval does not require the word INFO. The scaffold holds a plain docs/ config, a customRules config under tools/, a .cjs config under scripts/ and a gitignored node_modules decoy; md_config_state reads them as plain, code, code, and README.md as none. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, check, read-only, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Says the repository is not covered: docs/ governs only its subtree and a root config would cover the tree; lists docs/, tools/ and scripts/ with their scope; reports tools/ and scripts/ as gated until the user approves; lists no node_modules config; creates no approval marker; no install, lint run, write or edit."
---

/markdown-format:setup check

We have a markdownlint config under docs/ but none at the repo root. Is the whole repo covered? List every config you find with the directories it governs, and say for each whether markdownlint-cli2 runs under it today.
