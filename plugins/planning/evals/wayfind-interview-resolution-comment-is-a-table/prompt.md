---
description: "wayfind evals.json case 25, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The resolution comment states the agreed result as a table (OAuth client credentials for partners, API keys for the sandbox), then lists out of scope, deferred (mutual TLS), glossary changes ('partner app') and what later items inherit (per-client identity for the rate-limit item). Then the Decisions-so-far pointer is added and the item closed."
---

/planning:wayfind work 'Map: partner API v2' (#400). The claimed interview item 'Choose the auth scheme' (#402) is settled with the user: OAuth client credentials for partners, API keys only for the sandbox, mutual TLS deferred to a later phase, 'partner app' added to the glossary, and the rate-limit item will inherit the per-client identity. Post the resolution and close it.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
