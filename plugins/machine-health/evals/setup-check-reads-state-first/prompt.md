---
description: "Bare /machine-health:setup runs check: it reads the shipped catalog first and reports the current state (27 shipped checks, the overlay's one patch, the approved and unapproved remediations, the pending proposals) before offering any change, and writes nothing (setup/SKILL.md 'check', step 1 of the interview). Narration for the state folder: the run's plugin-data folder is denied by the sandbox and the split-root probe reads ~/.claude, so the prompt gives that state as facts and the case grades the report. reads-shipped-catalog (with-only, a plugin file) checks the catalog Read; counts-shipped-checks and names-unapproved-remediation need facts only the plugin holds; reports-before-changing judges the rest. Slash-invoked (disable-model-invocation), so there is no Skill grader."
tags: [machine-health, setup, check, narration, invented]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run reads skills/audit/catalog/checks.jsonc. The reply opens with the current state: 27 checks ship, the overlay turns off battery, clear-temp-files is approved and restart-stopped-service is not, and two proposals wait. It offers changes only after that summary, frames setup as safe to re-run, and writes or replaces nothing."
---

/machine-health:setup

Set up machine-health for this machine. The state-folder probes are done; take these facts as given and do not read, list or probe anything under the plugin data folder or ~/.claude:

- The state root resolved and exists, and no split root was found.
- The catalog overlay holds one entry, which turns off the battery check.
- The approvals file approves clear-temp-files and nothing else.
- There is no mutes file.
- The pending-proposals file holds two proposals.
- There is no monthly wrapper copy and no status file.

Write nothing. Start your reply with a summary: how many checks ship, which checks the overlay patches, which remediations are approved or not, and how many proposals wait for a decision.
