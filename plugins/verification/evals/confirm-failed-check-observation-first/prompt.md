---
description: 'A failed check whose capture read a stale artifact. The report names the observation (probe, driver, capture, environment) as the first suspect and what the run did to rule it in or out, in an Observation check line, before any verdict against the change. names-observation-check grades the report line; observation-suspected-first (llm) grades the order and the ruling.'
tags: [verification, confirm, narration, no-network, outcome, observation, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'Names the stale screenshot as the first suspect, says what rules it in (its timestamp predates the rebuild) and what it does next (capture again after the rebuild, or read the page by a second route), carries an Observation check line in the report, and renders no NEEDS WORK against the change on that capture alone.'
---

/verification:confirm outcome. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. The plan adds an Export button to the reports page, and the diff adds it. The capture check for the reports page failed: the screenshot it compared shows no Export button. The screenshot file's modified time is 14:02; the rebuild that includes the diff finished at 14:09. Write the Assessment section of your report and the verdict, then stop.
