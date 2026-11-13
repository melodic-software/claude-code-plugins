---
description: "wayfind evals.json case 2, run as a plugin-eval case for the before/after comparison (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Work mode picks #145 as the frontier item, claims it (assignee plus a claim-comment lease), and routes the decision by invoking /planning:design directly — since design-typed items route there — rather than deciding the aggregate boundaries itself inline."
---

/planning:wayfind work — on our map (#142), the next open, unblocked, unassigned item is #145, labeled 'wayfind: design', asking us to choose the aggregate boundaries for the new billing domain. Resolve it.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
