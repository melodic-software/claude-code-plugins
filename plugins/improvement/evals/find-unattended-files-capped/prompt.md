---
description: "Legacy find case unattended-declaration-no-questions-persisted-report. Narration: the run cannot run the state-key helper (no Bash), the sandbox denies the plugin data folder and no tracker plugin loads, so the prompt gives the state key and the open items as facts and switches writes and filing off; the case grades the declared plan, not a real write or filing. The caller declares unattended mode and a cap of 2. The reply names the report path under the plugin data folder at find/<state-key>/reports/improvement-<timestamp> (report-path-under-plugin-data), writes nothing into the target repository (no-repo-write) and edits nothing (no-edit), asks no question (no-ask-tool, no-question-in-reply), names #41 as the duplicate it does not file (skips-duplicate-41), and files at most two items without prioritizing, closing or reordering the queue (cap-and-no-self-disposal, llm). The real report write and real filing are unmeasured. Needs --scaffold and --allow-tools Write Edit so the write graders can fail."
tags: [find, unattended, narration, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, AskUserQuestion]
expected_outcome: "The run asks nothing, names ${CLAUDE_PLUGIN_DATA}/find/github.com/acme/checkout-service/3f9a1c2e/reports/improvement-<UTC timestamp>.md as the report path, says the instrument-checkout candidate duplicates open item #41 so it is not filed, lists at most two items it would file, and neither writes into the repository nor prioritizes or closes any item."
---

/improvement:find --unattended

This runs unattended as a scheduled routine; there is no interactive user to answer any question. File at most 2 items this run.

Facts for this run, take them as given: the plugin's state-key helper printed `github.com/acme/checkout-service/3f9a1c2e`. work-items:track is installed and bound to this repository's tracker, and its open items are #41 "Instrument checkout timing so speed work can be ranked on data" and #57 "Upgrade the test runner". No candidate has been dismissed before. Writes and tracker calls are switched off in this sandbox, so write nothing and invoke no work-items skill: instead give the exact path the report would be persisted to, and for each top candidate say what the filing step decides and the title of any item it would file.
