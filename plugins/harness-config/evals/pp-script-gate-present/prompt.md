---
description: "Hard. Phase C mechanical-gate rule: before judging a destructive-capable component MISSING on P7, follow and read the script it delegates the action to; 'a component whose destructive step runs through a script that performs the approval check is gated'. wipe-cache delegates to scripts/wipe-cache.sh, which asks y/N before deleting. Hard because the skill's own text carries no confirmation and the user suggests adding one. At risk in the sandbox: Phase D persists last-audit.md under ${CLAUDE_PLUGIN_DATA}, which the sandbox denied on slice A; graders read the chat report and tool calls only. Needs network: Phase A aborts when the best-practices page cannot be fetched. Needs --scaffold --allow-tools Bash Write WebFetch Agent."
tags: [hard, audit-prompting-postures, outcome, presence-evidence, scaffold, plugin-data-risk]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, WebFetch, Agent]
expected_outcome: "The best-practices guide is fetched; the reply judges wipe-cache PRESENT on destructive-action confirmation, citing the y/N prompt in scripts/wipe-cache.sh, and writes nothing."
---

/harness-config:audit-prompting-postures skills

The wipe-cache skill deletes files. Does it need a confirmation step added?
