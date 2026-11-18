---
description: "Unattended find whose team config sets the per-run filing cap. Narration: a scaffolded .claude/improvement.md sets find_run_item_cap to 1, and the prompt gives the tracker's state as facts and switches writes and filing off. The reply asks nothing (no-ask-tool), writes and edits nothing in the repository (no-repo-write, no-edit), reads the team layer (reads-team-layer), and plans one filing because the configured cap is 1 (files-one-item-from-config, llm). Real filing is unmeasured. Needs --scaffold and --allow-tools Write Edit so the write graders can fail."
tags: [find, unattended, narration, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, AskUserQuestion]
expected_outcome: "The run asks nothing, reads find_run_item_cap: 1 from the team config, and plans to file exactly one item under source: improvement-find, leaving the other candidates in the report."
---

/improvement:find --unattended

This runs unattended as a scheduled routine; there is no interactive user to answer any question.

Facts for this run, take them as given: the plugin's state-key helper printed `github.com/acme/checkout-service/3f9a1c2e`. Read the config layers in this workspace yourself; no user-global layer exists. work-items:track is installed and bound to this repository's tracker, the repository has the `source: improvement-find` label, and no open item carries it. This is the first unattended run, so no earlier filing or dismissal exists. architecture:improve is not available. Writes and tracker calls are switched off in this sandbox, so write nothing and invoke no work-items skill: instead give the exact path the report would be persisted to, state the per-run filing cap in effect and where it came from, and give the title and source label of each item it would file.
