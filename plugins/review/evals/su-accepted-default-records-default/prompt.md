---
description: "setup apply with the operator accepting the plugin default for ratchet_offer and choosing report for downstream_probe: the writer gets --default ratchet_offer and downstream_probe=report, and the new docs/conventions/review.yaml records ratchet_offer as default, downstream_probe as chosen, and written_against. Needs --scaffold --allow-tools Bash Write Edit."
tags: [review, setup, outcome, provenance, scaffold]
max_turns: 16
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "setup-apply.mjs runs with --default ratchet_offer and downstream_probe=report, never with ratchet_offer=<value>; the written docs/conventions/review.yaml holds written_against: review@<version>, a provenance entry ratchet_offer: default and an entry downstream_probe: chosen (default run)."
---

/review:setup apply

My answers to the settings, so you need not ask:

- ratchet_offer: I take the plugin's default, whatever it is now. If a later plugin version changes that default, I want the new one.
- downstream_probe: report. The team decided this; keep it.
- fanout_diversity: leave it unset.

If setup asks about a convention home, skip that for now.
