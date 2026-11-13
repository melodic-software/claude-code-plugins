---
description: "wayfind evals.json case 9, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Work mode graduates #44 (resolution comment, Decisions-so-far pointer, close), charts 'Choose per-tenant invoice storage' as a typed item and deletes the matching fog bullet from Not-yet-specified, then sweeps the map: #47 is closed as moot with a comment linking #44's resolution and gets no index line; #39 is not reopened or edited, a new decision item linking #39 is opened to revisit the table design, and #39's Decisions-so-far line is rewritten to point at the decision that supersedes it once that resolves."
---

/planning:wayfind work #200 'Map: billing overhaul'. We just resolved #44 'Decide invoice numbering': invoices are numbered per tenant, not globally. That makes open item #47 'Pick the global invoice sequence store' pointless. It also shows closed decision #39 'Share one invoice table across tenants' was wrong. The map's Not-yet-specified section says 'something feels off about how tenants share invoice data'; the resolution makes that sharp enough to chart as 'Choose per-tenant invoice storage'. Finish the close-out.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
