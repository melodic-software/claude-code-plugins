---
description: "Unattended work mode filters the frontier by the human-gated label the tracker binding sets (owner-call), not the shipped default, and finds the map by its decide: map label (after-only)."
tags: [wayfind, wayfind-charting, after-only, label-prefix]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The binding sets the human-gated label to owner-call, so in this unattended run 'Decide what the digest promises a first-time reader' (owner-call) is filtered off the frontier even though it carries no needs-human label. The run claims 'Pick the digest batching window' and routes it by its decide: design label to /planning:design. Any open-map listing it writes out filters by decide: map."
---

/planning:wayfind work — running unattended in a scheduled loop; no one will answer questions.

The tracker's current state is exported under tracker-export/ in the working directory: read it. (Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
