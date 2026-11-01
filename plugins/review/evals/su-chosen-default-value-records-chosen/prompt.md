---
description: "setup apply ratchet_offer=true, a value equal to the plugin default that the operator chose on purpose: the writer gets ratchet_offer=true, never --default ratchet_offer, and the new docs/conventions/review.yaml records ratchet_offer as chosen (default true). Needs --scaffold --allow-tools Bash Write Edit."
tags: [review, setup, outcome, provenance, scaffold]
max_turns: 16
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "setup-apply.mjs runs with ratchet_offer=true and never with --default ratchet_offer; the written docs/conventions/review.yaml holds written_against: review@<version> and the provenance entry ratchet_offer: chosen (default true), never ratchet_offer: default."
---

/review:setup apply ratchet_offer=true

The team chose true on purpose. Keep it true even if a later plugin version changes the default.
Leave every other setting unset. If setup asks about a convention home, skip that for now.
