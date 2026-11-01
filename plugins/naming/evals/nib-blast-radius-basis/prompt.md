---
description: "Routing case on an existing name: `calcTotal` undersells what the function does (it also applies the coupon and the tax). When the target already has a name, the shortlist states its call-site blast radius, counted by a search this session, and the pick carries a `Basis:` label, verified with file:line or tool output, or judgment (SKILL.md 'Default pass' step 4, lines 156-168). The fixture holds the definition plus three referencing files. The Basis label is this plugin's convention, so a no-plugin baseline likely omits it. No gated tool is listed; Grep is the search."
tags: [naming, name-it-better, outcome, routing, blast-radius, basis, scaffold, invented]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "The run invokes naming:name-it-better, searches the repo for calcTotal, and replies with a ranked shortlist whose recommended pick states the rename's blast radius (the definition in src/cart/total.js plus references in src/cart/cart.js, src/billing/invoice.js and test/total.test.js) and a Basis: label (verified, citing the search, or judgment). It renames nothing and leaves the choice to the user."
---

`calcTotal` in src/cart/total.js is a poor name; it also takes the coupon off and adds the tax, so callers keep assuming it is a plain sum. Help me find a better one.
