---
description: "wayfind evals.json case 11, run as a plugin-eval case for the before/after comparison (after-only). Narration: the prompt names an interview ledger no fixture provides."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Chart's proposed map seeds from the ledger: the two settled answers go into one seed decision item whose resolution comment lists them, closed at once with one Decisions-so-far pointer; the two open questions become decision items; the derived-analytics deletion worry is a labeled Not-yet-specified bullet. It does not open one closed issue per settled answer and does not cite the .work path in Notes."
---

/planning:wayfind chart the data-retention program. Our interview ledger is at .work/data-retention/interview-checklist.md: it settled 'retain audit logs 7 years' and 'EU data stays in the EU region', and left open 'Which stores hold personal data?' and 'Do backups count as retained copies?'. We also still can't say what 'deletion' should mean for derived analytics. I confirm the destination: a PRD for the retention program.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
