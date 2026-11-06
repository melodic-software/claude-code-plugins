---
description: "setup apply over an existing committed config. setup is user-invoked only (disable-model-invocation: true), so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 14-17: re-running reads the existing config and offers updates rather than overwriting blind; lines 55-59: start from the effective config check reported and propose changes against that baseline, nothing dropped without the user confirming. The committed .claude/codebase-health.md lists a docs/**/*.md glob the repo has no files for and a custom api-contracts dimension a fresh inference would not produce, so a blind rewrite would drop it. reads-existing grades a Read of the config file; summarizes-baseline a reply naming both its dimensions; proposes-against-baseline (llm) changes proposed against the file with api-contracts kept; no-config-write and no-config-edit no write in this turn; config-kept that the file still holds the api-contracts section; no-plugin-dir-write that nothing is written into the plugin or plugin data directory (lines 103-104). AskUserQuestion is left out so the ask lands in the reply text. Needs --scaffold --allow-tools Bash Write Edit."
tags: [codebase-health, setup, outcome, idempotent, no-network]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The run reads .claude/codebase-health.md, the reply summarizes its documentation and api-contracts dimensions and proposes changes against them, and the file is neither written nor edited, so its api-contracts section survives. Nothing is written into the plugin directory."
---

/codebase-health:setup apply
