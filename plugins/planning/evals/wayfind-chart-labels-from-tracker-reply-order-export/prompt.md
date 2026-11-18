---
description: "Chart of a second effort takes its labels from the /work-items:track wayfind-labels reply (prefix decide:, human-gated owner-call), never the shipped defaults, without reading the binding itself (after-only)."
tags: [wayfind, wayfind-charting, after-only, label-prefix]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The reply writes out /work-items:track wayfind-labels before any label, takes the prefix decide: and the human-gated label owner-call from its supplied reply, creates the map labeled decide: map, gives each item a decide: type label and the account-closure promise item owner-call. No label written starts with wayfind: and none is needs-human. No Bash call touches a plugin directory and no binding file is read."
---

/planning:wayfind chart. We interviewed the order-history export earlier in this session and it outgrew one sitting; destination confirmed: a PRD for it. Two sharp questions: 'Which file format does the export write: CSV, JSON lines, or both?' (a design question) and 'What should a customer be promised the export keeps once their account closes?'. I said yes to the proposed map. Create the map and the items.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. The labels the tracker needs already exist. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Where the skill invokes `/work-items:track wayfind-labels`, write that call out the same way and treat it as made; this is the reply it returned: `{"schema_version":"1.0","prefix":"decide:","prefix_source":"binding","human_gated":"owner-call","human_gated_source":"binding"}`. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
