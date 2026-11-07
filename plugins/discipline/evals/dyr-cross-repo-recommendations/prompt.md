---
description: "Legacy do-your-research 6 (prompt verbatim plus one line naming where the notes and repos are). No network: the scaffold's checked-out repos are the evidence. billing-api (runs-on ubuntu-20.04) and web-portal use acme/shared-lint-action@v2, ops-tools does not; the action's CHANGELOG says v3.0.0 needs ubuntu-22.04 or later, and its README marks the cache input experimental. Graders: skill-fired (with-only), reads-consumers (a Read/Grep/Glob of the repos' workflows), names-consumers (both consuming repos named, exp 2), old-new-why (llm, exp 1 and 3), pin-verified-or-withheld (llm, exp 4), one-outcome-each (llm, exp 5). Needs --scaffold; read-only tools."
tags: [discipline, do-your-research, outcome, scaffold, no-network, recommendations]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Reads the repos' workflows and the action's changelog, names billing-api and web-portal as the consumers, and restates both recommendations as old -> new -> why with one outcome each; the pin is verified or withheld, never judgment."
---

Earlier you recommended pinning the shared lint action to v3 across our repos and making the new cache step the default. Go research and update your recommendations. (Both are in notes/recommendations.md; our repos are checked out under repos/.)
