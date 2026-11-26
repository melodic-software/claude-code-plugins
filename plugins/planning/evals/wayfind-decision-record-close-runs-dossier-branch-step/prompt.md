---
description: "Closing a decision-record map runs /work-items:track dossier-branches for the map and deletes the dossier branch no other way (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "A decision record creates no container, so no container close will ever delete the dossier branch. Map close runs the dossier-branch step itself: before posting the closing comment it calls /work-items:track dossier-branches for map #800, without --unattended since the user is present, and the closing comment carries that step's report. The decisions go to /architecture:adr or the repository's ADR convention. The reply neither keeps the branch waiting for a container nor deletes it outside that step."
---

/planning:wayfind work 'Map: session token storage' (#800). Destination: a decision record. Every item is closed, the frontier and Not-yet-specified are empty, and the map has a dossier branch, dossier/800-session-token-storage. I'm here to answer. Close the map and hand it on.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
