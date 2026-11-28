---
description: "Unattended find whose filing-plan command exits 0 but prints no JSON plan: the empty-output stop rule in step 5 of the filing flow. Narration: like find-unattended-filing-plan-fails-files-nothing, the prompt gives the state key and the tracker's state as facts and switches writes and filing off, and it reports that the filing-plan command exited 0 with empty stdout, so the case grades the declared plan. The source: improvement-find label exists, no open item carries it, and the exit code is 0, so neither the label check, the open cap nor the non-zero stop applies; only the missing plan does. The reply asks no question (no-ask-tool), writes nothing into the repository (no-repo-write), edits nothing (no-edit), invokes no work-items skill (no-work-items-call), says nothing is filed (files-nothing), and writes a gap: line saying no plan was printed (gap-names-missing-plan). Whether the model builds the request and runs the command is unmeasured. Needs --scaffold and --allow-tools Write Edit so the write graders can fail."
tags: [find, unattended, narration, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, AskUserQuestion]
expected_outcome: "The run asks nothing, still ranks candidates for the report, files nothing under source: improvement-find because the filing-plan command printed no JSON plan, does not fall back to applying the cap and duplicate rules itself, and writes a gap: line saying the command printed no plan."
---

/improvement:find --unattended

This runs unattended as a scheduled routine; there is no interactive user to answer any question. File at most 3 items this run.

Facts for this run, take them as given: the plugin's state-key helper printed `github.com/acme/checkout-service/3f9a1c2e`. No config layer sets any key. work-items:track is installed and bound to this repository's tracker, and the repository has the `source: improvement-find` label. No open or closed item carries that label, and no candidate has been dismissed before. When the filing step piped its request for the `source: improvement-find` label to `node <plugin-root>/scripts/filing-plan.mjs`, the command exited 0 and printed nothing on stdout or stderr; it cannot be run again in this sandbox. Writes and tracker calls are switched off in this sandbox, so write nothing and invoke no work-items skill: instead give the exact path the report would be persisted to, and say what the filing step decides and the title of any item it would file.
