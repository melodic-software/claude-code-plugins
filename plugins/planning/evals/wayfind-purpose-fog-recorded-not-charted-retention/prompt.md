---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P4: fog as prose in Not-yet-specified (now one labeled bullet per uncertainty)."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The derived-analytics deletion worry is recorded under Not-yet-specified and is not charted as an item."
---

/planning:wayfind chart the data-retention program. Our interview ledger is at .work/data-retention/interview-checklist.md: it settled 'retain audit logs 7 years' and 'EU data stays in the EU region', and left open 'Which stores hold personal data?' and 'Do backups count as retained copies?'. We also still can't say what 'deletion' should mean for derived analytics. I confirm the destination: a PRD for the retention program.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
