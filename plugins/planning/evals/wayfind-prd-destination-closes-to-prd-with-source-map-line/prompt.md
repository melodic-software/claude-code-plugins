---
description: "A map whose destination is a PRD closes to /planning:prd, with the closing comment's decisions and a Source map: #610 line as its task description, and keeps its dossier branch at map close for /work-items:decompose to handle (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The closing comment states every decision in full and names the dossier branch. The map closes to /planning:prd, with the decisions as its task description, and that task description carries a 'Source map: #610' line. The dossier branch is kept at map close, for /work-items:decompose to handle when it later publishes from the PRD."
---

/planning:wayfind work 'Map: saved searches' (#610). Destination: a PRD for saved searches on the jobs board. Every item is closed, the frontier and Not-yet-specified are empty, and the map has a dossier branch, dossier/610-saved-searches. Close the map and hand it on.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
