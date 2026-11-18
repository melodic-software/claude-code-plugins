---
description: "When /work-items:track wayfind-labels refuses, chart stops and reports the refusal: no map, no item, no default label, and no reading the binding itself (after-only)."
tags: [wayfind, wayfind-charting, after-only, label-prefix]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The reply writes out /work-items:track wayfind-labels, reads its supplied REFUSED: reply as a stop, reports the refusal (the convention home does not resolve; /work-items:setup check), and creates no map or item, so it writes no label, wayfind: or needs-human included. No Bash call touches a plugin directory and no binding file is read."
---

/planning:wayfind chart. We interviewed the weekly notification digest earlier in this session and it outgrew one sitting; destination confirmed: a PRD for it. Two sharp questions: 'Which batching window sends one digest per reader: a fixed weekday, a rolling seven days, or a count threshold?' (a design question) and 'What should the digest promise a first-time reader?'. I said yes to the proposed map. Create the map and the items.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. The labels the tracker needs already exist. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Where the skill invokes `/work-items:track wayfind-labels`, write that call out the same way and treat it as made; this is the reply it returned: `REFUSED: work-item-tracker: no convention home resolves under /work/acme-mail; run /work-items:setup check to see why`. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
