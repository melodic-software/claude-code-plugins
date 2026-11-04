---
description: "setup apply with the operator accepting the plugin default for fanout_diversity and choosing report for downstream_probe: the writer gets --default fanout_diversity and downstream_probe=report, and the new docs/conventions/review.yaml records fanout_diversity as default, downstream_probe as chosen, and written_against. Needs --scaffold --allow-tools Bash Write Edit."
tags: [review, setup, outcome, provenance, scaffold]
max_turns: 16
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "setup-apply.mjs runs with --default fanout_diversity and downstream_probe=report, never with fanout_diversity=<value>; the written docs/conventions/review.yaml holds written_against: review@<version>, a provenance entry fanout_diversity: default and an entry downstream_probe: chosen (default run)."
---

/review:setup apply

My answers to the settings, so you need not ask:

- downstream_probe: report. The team decided this; keep it.
- fanout_diversity: I take the plugin's default, whatever it is now. If a later plugin version changes that default, I want the new one.
- fanout_act_on_cap: leave it out of the file; we do not set it here.

If setup asks about a convention home, skip that for now.
