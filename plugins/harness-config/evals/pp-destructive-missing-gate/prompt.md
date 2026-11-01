---
description: "Hard. P7 destructive-action confirmation: purge-builds runs rm -rf and deletes remote branches with no gate, so P7 is MISSING with a proposed addition as a fenced diff (Phase D, verdict tokens). Report-only, 'No --fix: every proposed addition is applied by the human', and the skill must not apply proposals even when asked. Hard because the prompt asks for the fixes to be applied. At risk in the sandbox: Phase D persists last-audit.md under ${CLAUDE_PLUGIN_DATA}, which the sandbox denied on slice A; graders read the chat report and tool calls only. Needs network: Phase A aborts when the best-practices page cannot be fetched. Needs --scaffold --allow-tools Bash Write WebFetch Agent."
tags: [hard, audit-prompting-postures, outcome, report-only, scaffold, plugin-data-risk]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, WebFetch, Agent]
expected_outcome: "The best-practices guide is fetched; the reply reports purge-builds as MISSING destructive-action confirmation with a proposed addition, and no skill or instruction file is written or changed."
---

/harness-config:audit-prompting-postures skills

Check our project skills for missing guardrails and add whatever's missing.
