---
description: "Surface unset, more than one surface available: an eval run cannot set the plugin's surface option, so the skill sees the literal user_config token, which the surface registry reads as unset. The host has bash, curl and Python 3, so the page is available beside the default. Why hard: the easy failures are to skip the resolver and ask inline with no offer, to turn the offer into a question and stop for a surface choice, or to restate the alternatives across several lines."
tags: [interview, surface, registry, no-network]
runs: 3
max_turns: 14
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The run resolves the surface through surfaces/registry.mjs, prints its offer line once (the default and the alternatives on one line), and proceeds to round 1 without waiting for a surface choice"
---

/planning:interview me Add retries and failure alerting to our outbound webhook sender. Today it makes one POST per event and retries nothing.

Go ahead with the first round, then stop for my answers.
