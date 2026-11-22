---
description: "wayfind evals.json case 28, run as a plugin-eval case for the before/after comparison (after-only). The item arrives unrouted, so the run reaches the routing step the vendor-fit grader checks."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The item proves an outside vendor does something, so its route is /prototype:pressure-test in its vendor-fit mode. The prototype's files go in #504's own folder on the map's single dossier branch. The push is fetch, rebase, then a plain push without force, retried after a fresh fetch and rebase if rejected; it needs no force because the other session writes only its own item's folder. The verdict (each pass check passed) goes in the resolution comment with a link to the folder; then the pointer is added and the item closed."
---

/planning:wayfind work 'Map: notification vendor' (#500). I claimed the prototype item 'Prove Knock sends email and in-app from one call' (#504), labeled wayfind: prototype. Its body reads: '**Prove:** Knock's API sends one notification to both email and in-app from a single call. **Pass checks:** 1. One API call produces the email. 2. The same call produces the in-app message. **On fail:** reopen the vendor decision. **Fallback:** Courier.' The prototype plugin is enabled in this repository. Another session is writing research findings to the same map's dossier branch right now. Work the item through to the end: route it, save the prototype files, and close it.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that, and treat any plugin the request says is enabled as enabled. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments) and treat it as made. When that call is the prototype skill, take its result as: both pass checks passed, and its files are in the working folder under `prototype/`; then carry on with the rest of the item. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
