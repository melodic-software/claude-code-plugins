---
description: "wayfind evals.json case 35: a domain/event-model design item falls back to /planning:design when the event-storming plugin is not enabled (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The item is domain/event-model work, which would route to /event-storming:methodology or /event-storming:simulation, but the event-storming plugin is not enabled, so the item falls back to /planning:design. The skill does not settle the event model itself inline and does not stop for the missing plugin."
---

/planning:wayfind work 'Map: order fulfilment' (#900). The claimed item 'Model the order lifecycle events' (#903, wayfind: design) asks which domain events an order goes through from placement to delivery. The event-storming plugin is not enabled in this repository. Work it.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
