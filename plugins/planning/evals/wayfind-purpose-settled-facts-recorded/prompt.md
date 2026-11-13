---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P3 chart side: interview facts, constraints and glossary distilled into Notes (now constraints in Notes, facts and glossary in the seed item's resolution comment)."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Each of the ledger's settled answer, constraint, self-answered fact and glossary entry is recorded somewhere durable on the tracker in the output's plan."
---

/planning:wayfind chart the invoice-export effort. Our interview ledger is at .work/invoice-export/interview-checklist.md and the effort outgrew one sitting; destination confirmed: a PRD.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
