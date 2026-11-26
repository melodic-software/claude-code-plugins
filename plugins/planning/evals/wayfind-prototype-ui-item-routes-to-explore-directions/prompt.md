---
description: "A prototype item whose Prove line says UI routes to /prototype:explore-directions, not /prototype:pressure-test or /planning:design (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The item routes by its wayfind: prototype label to the prototype skills, and because its Prove line says UI, to /prototype:explore-directions, not /prototype:pressure-test. It does not go to /planning:design even though its subject is a screen layout."
---

/planning:wayfind work 'Map: notification vendor' (#500). The claimed item 'Settle the channel mute controls' (#506) carries the wayfind: prototype label. Its body reads: '**Prove:** UI: a settings screen where a user mutes email, push and in-app per notification type reads clearly at a glance. **Pass checks:** 1. A first-time user finds how to mute push for order updates in under ten seconds. 2. The muted state of every channel is visible without scrolling. **On fail:** reopen the preferences layout decision. **Fallback:** one global mute per channel.' The prototype plugin is enabled in this repository. I'll judge the variants. Work it.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker, write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments) and stop there. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to.)
