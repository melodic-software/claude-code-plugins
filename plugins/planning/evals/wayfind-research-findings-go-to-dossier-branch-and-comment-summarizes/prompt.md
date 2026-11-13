---
description: "wayfind evals.json case 22, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Work dispatches /discovery:research for #305, asking for its lightest verification level (light) with no separate verifier pass. When it returns, it copies the findings file and its sidecars into #305's own folder on the map's dossier branch, creating that branch on first use and linking it from Notes, and pushes with fetch, rebase and a plain push. The resolution comment gives the pick and why, its costs, how the alternatives compare, what could not be verified, and a link to the full findings file; then the Decisions-so-far pointer is added and the item closed."
---

/planning:wayfind work 'Map: search rewrite' (#300). The claimed item 'Pick the index library' (#305, wayfind: research) is ready to run. The map has no dossier branch yet. Run the research and graduate the item.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
