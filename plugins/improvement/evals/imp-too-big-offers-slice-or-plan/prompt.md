---
description: "Legacy improve case too-big-hands-off-to-plan, local half. Narration: the sandbox has no network, so the prompt gives the upstream finding as a fact (the request package is deprecated and Node ships a global fetch); grounding the currency focus in fetched upstream guidance with cited sources is held. The scaffold puts 20 request-based modules under src/checkout/, more files than the PR scope budget's hard cap. The reply says the whole change is past the cap (names-cap-exceeded), offers a smaller complete slice or /planning:plan (offers-slice-or-plan) and ends by asking which the user wants (asks-for-choice), and makes no edit, branch, commit, push or pull request before the answer (no-edit, no-branch-commit-or-pr). Needs --scaffold and --allow-tools Bash Edit so the must-not graders can fail."
tags: [improve, scope-budget, narration, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Edit, Bash]
expected_outcome: "The reply finds that moving all 20 checkout modules off request exceeds the hard cap (15 files, 400 lines), does not start the change, offers a smaller complete slice that fits or /planning:plan for the whole migration, and asks the user to choose."
---

/improvement:improve the checkout feature --focus currency. I'm here to answer questions.

The network is unavailable in this sandbox, so take this upstream finding as given instead of researching it: the `request` package is deprecated upstream, and Node.js 18 and later ship a global `fetch` that replaces it.
