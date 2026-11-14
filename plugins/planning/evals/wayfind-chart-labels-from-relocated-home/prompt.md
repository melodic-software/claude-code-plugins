---
description: "Chart reads the tracker binding at a convention home the root AGENTS.md pointer moves to config/team (prefix decide:, human-gated owner-call), never the shipped defaults (after-only)."
tags: [wayfind, wayfind-charting, after-only, label-prefix]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The root AGENTS.md convention-home region points at config/team, and config/team/work-items.yaml sets the wayfind prefix to decide: and the human-gated label to owner-call; docs/conventions holds no binding. The map is created labeled decide: map, each item carries a decide: type label, and the archive-promise item carries owner-call. No label written starts with wayfind: and none is needs-human."
---

/planning:wayfind chart. We interviewed the order-history export earlier in this session and it outgrew one sitting; destination confirmed: a PRD for it. Two sharp questions: 'Which file format does the export write: CSV, JSON lines, or both?' (a design question) and 'What should a customer be promised the export keeps once their account closes?'. I said yes to the proposed map. Create the map and the items.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. The labels the tracker needs already exist. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
